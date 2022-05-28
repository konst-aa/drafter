defmodule Drafter.Pod.Server.State do
  defstruct [:status, :set, :option, :group, :loader_name, :player_map, :conditions]
  
  alias Drafter.Structs.Player

  @type pod_string :: String.t()

  @type set :: String.t()
  @type option :: String.t()
  @type channelID :: Nostrum.Struct.Channel.id()
  @type pod_pid :: pid()
  @type loader_name :: atom()
  @type direction :: :left | :right

  @typep pack_number :: integer()
  @typep conditions :: %{direction: direction(), pack_number: pack_number()}
  @typep waiting_group :: %{Player.playerID() => boolean()}

  @typep waiting_state :: %__MODULE__{
           status: :waiting,
           set: set(),
           option: option(),
           group: waiting_group()
         }

  @typep running_state :: %__MODULE__{
           status: :running,
           option: option(),
           loader_name: loader_name(),
           player_map: Player.player_map(),
           conditions: conditions()
         }

  @type t :: running_state() | waiting_state() 

  # running
  @spec read_cur_pack(loader_name(), Player.t(), pack_number()) :: :ok
  defp read_cur_pack(loader_name, %Player{dm: dm, backlog: backlog}, pack_number) do
    [pack | _] = backlog
    content = "pack #{pack_number} pick #{16 - length(pack)}"
    Nostrum.Api.create_message(dm.id, content)
    Packloader.Server.send_cards(loader_name, dm, pack)
  end

  @spec crack_and_read_all(loader_name(), Player.player_map(), pack_number()) ::
          Player.player_map()
  defp crack_and_read_all(loader_name, player_map, pack_number) do
    new_players = Player.crack_all(player_map)

    Enum.map(new_players, fn {_, playerID} ->
      read_cur_pack(loader_name, playerID, pack_number)
    end)

    new_players
  end

  @spec gen_running_state(waiting_state()) ::
          running_state() | :nullset
  defp gen_running_state(state) do
    %__MODULE__{set: set, option: option, group: group} = state
    contents = File.read!("./sets/sets.json")
    sets = JSON.decode!(contents)
    IO.puts("starting")

    case Map.get(sets, set, :undefined) do
      :undefined ->
        # send the message !
        # Kill the process? 
        :nullset

      set ->
        player_map = Player.gen_player_map(set, option, Map.keys(group), loader_name)

        # crack the packs
        pack_number = 1
        player_map = crack_and_read_all(loader_name, player_map, pack_number)

        # celebrate
        IO.puts("player_map generated, draft started")
        conditions = %{direction: :left, pack_number: pack_number}

         %__MODULE__{
           loader_name: loader_name,
           option: option,
           player_map: player_map,
           conditions: conditions,
           status: :running
         }
    end
  end

  # running
  @spec flip(:right) :: :left
  defp flip(:right), do: :left
  @spec flip(:left) :: :right
  defp flip(:left), do: :right
  
  # rewrite this probably?
  @spec passed_messages(
          loader_name(),
          Player.playerID(),
          Player.player_map(),
          direction(),
          pack_number()
        ) :: :ok | nil | :passed | :next | :over
  defp passed_messages(loader_name, playerID, player_map, direction, pack_number) do
    crack? =
      player_map
      |> Map.values()
      |> Enum.map(fn x -> Map.get(x, :backlog) end)
      |> Enum.all?(fn backlog -> backlog == [[]] end)

    unless crack? do
      playerID = Map.get(player_map, playerID)
      targetID = Player.pull_direction(playerID, direction)
      target = Map.get(player_map, targetID)

      case playerID do
        %Player{backlog: [[] | _]} -> nil
        %Player{backlog: [_pack | _]} -> read_cur_pack(loader_name, playerID, pack_number)
        _ -> nil
      end

      case target do
        %Player{backlog: [[] | _]} -> nil
        %Player{backlog: [_pack | []]} -> read_cur_pack(loader_name, target, pack_number)
        _ -> nil
      end

      :passed
    else
      unless pack_number == 3 do
        # crack next pack
        :next
      else
        # draft over
        :over
      end
    end
  end

  # server
  @spec init({set(), option(), Player.group()}) :: waiting_state()
  def init({set, option, group}) do
    %__MODULE__{
      set: set, 
      option: option,
      status: :waiting, 
      group: Map.new(group, fn x -> {x, false} end)
    }
  end

  @spec ready(waiting_state(), Player.playerID(), channelID()) :: t()
  def ready(state, playerID, channelID) do
    %__MODULE__{group: group} = state
    group = Map.put(group, playerID, true)
    vals = Map.values(group)

    if Enum.all?(vals) do
      gen_running_state(state)
    else
      Nostrum.Api.create_message(channelID, "verified!")
      state
    end
  end

  # running state
  @spec pick(running_state(), Player.playerID(), Player.card_index()) :: running_state()
  def pick(state, playerID, card_index) do
    %__MODULE__{
      player_map: player_map, 
      loader_name: loader_name, 
      option: option, 
      conditions: conditions
    } =
      state

    case Player.pick(playerID, card_index, player_map) do
      {:outofbounds, _} ->
        # send messages
        state

      {:nopack, _} ->
        # send messages
        state

      {:ok, new_player_map} ->
        %{direction: direction, pack_number: pack_number} = conditions
        new_player_map = Player.pass_pack(playerID, direction, new_player_map)

        case passed_messages(loader_name, playerID, new_player_map, direction, pack_number) do
          :over ->
            # end the draft
            new_player_map
            |> Enum.map(fn {_id, player} -> Player.text_picks(player) end)
            |> Enum.map(fn {dm, msg} ->
              Nostrum.Api.create_message(dm.id, "draft over, picks: \n" <> msg)
            end)

            Process.exit(self(), :draftover)

          :next ->
            new_number = pack_number + 1
            new_player_map = crack_and_read_all(loader_name, new_player_map, new_number)
            new_conditions  = %{direction: flip(direction), pack_number: new_number}
            state
            |> Map.put(:player_map, new_player_map)
            |> Map.put(:conditions, new_conditions)
          :passed ->
            Map.put(state, :player_map, new_player_map)
        end
    end
  end

  @spec list_picks(running_state(), Player.playerID()) :: running_state()
  def list_picks(state, playerID) do
    %__MODULE__{player_map: player_map} = state
    {dm, msg} =
      player_map
      |> Map.get(playerID)
      |> Player.text_picks()
      # write loader ffs!!!! move text_picks out of player 
    Nostrum.Api.create_message(dm.id, msg)
    state
  end
end
