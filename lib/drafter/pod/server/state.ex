defmodule Drafter.Pod.Server.State do
  defstruct [:status, :set, :option, :group, :player_map, :conditions]

  alias Drafter.Structs.Player
  alias Drafter.Loaders.CardLoader
  alias Drafter.Loaders.SetLoader

  @type pod_string :: String.t()

  @type set :: String.t()
  @type option :: String.t()
  @type channelID :: Nostrum.Struct.Channel.id()
  @type pod_pid :: pid()
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
           player_map: Player.player_map(),
           conditions: conditions()
         }

  @type t :: running_state() | waiting_state()

  # running
  @spec read_cur_pack(Player.t(), pack_number()) :: :ok
  defp read_cur_pack(%Player{dm: dm, backlog: backlog}, pack_number) do
    [pack | _] = backlog
    CardLoader.send_pack(pack, 5, dm, "pack #{pack_number} pick #{16 - length(pack)}")
    :ok
  end

  @spec text_picks(Player.t()) :: :ok
  defp text_picks(%{dm: dm, picks: picks}) do
    picks_string =
      picks
      |> Enum.map(fn card -> Map.get(card, :name) end)
      |> Enum.join("\n")

    Nostrum.Api.create_message!(dm.id, "draft over, picks:" <> picks_string)
    :ok
  end

  @spec crack_and_read_all(Player.player_map(), pack_number()) ::
          Player.player_map()
  defp crack_and_read_all(player_map, pack_number) do
    new_players = Player.crack_all(player_map)

    Enum.map(new_players, fn {_, playerID} ->
      read_cur_pack(playerID, pack_number)
    end)

    new_players
  end

  @spec gen_running_state(waiting_state(), channelID()) ::
          running_state() | :nullset
  defp gen_running_state(state, channelID) do
    %__MODULE__{set: set, option: option, group: group} = state

    case SetLoader.load_set(set) do
      {:ok, set} ->
        player_map = Player.gen_player_map(set, option, Map.keys(group))

        # crack the packs
        pack_number = 1
        player_map = crack_and_read_all(player_map, pack_number)

        # celebrate
        IO.puts("player_map generated, draft started")
        conditions = %{direction: :left, pack_number: pack_number}

        %__MODULE__{
          option: option,
          player_map: player_map,
          conditions: conditions,
          status: :running
        }

      {:error, reason} ->
        Nostrum.Api.create_message!(channelID, "failure!" <> Atom.to_string(reason))
        :nullset
    end
  end

  # running
  @spec flip(:right) :: :left
  defp flip(:right), do: :left
  @spec flip(:left) :: :right
  defp flip(:left), do: :right

  # rewrite this probably?
  @spec passed_messages(
          Player.playerID(),
          Player.player_map(),
          direction(),
          pack_number()
        ) :: :ok | nil | :passed | :next | :over
  defp passed_messages(playerID, player_map, direction, pack_number) do
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
        %Player{backlog: [_pack | _]} -> read_cur_pack(playerID, pack_number)
        _ -> nil
      end

      case target do
        %Player{backlog: [[] | _]} -> nil
        %Player{backlog: [_pack | []]} -> read_cur_pack(target, pack_number)
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
      gen_running_state(state, channelID)
    else
      Nostrum.Api.create_message(channelID, "verified!")
      Map.put(state, :group, group)
    end
  end

  # running state
  @spec pick(running_state(), Player.playerID(), Player.card_index()) :: running_state()
  def pick(state, playerID, card_index) do
    %__MODULE__{
      player_map: player_map,
      option: _option,
      conditions: conditions
    } = state

    case Player.pick(playerID, card_index, player_map) do
      {:outofbounds, _} ->
        # send messages
        state

      {:nopack, _} ->
        # send messages
        state

      {:ok, new_player_map} ->
        dm =
          new_player_map
          |> Map.get(playerID)
          |> Map.get(:dm)

        Nostrum.Api.create_message(dm.id, "pack passed")
        %{direction: direction, pack_number: pack_number} = conditions
        new_player_map = Player.pass_pack(playerID, direction, new_player_map)

        case passed_messages(playerID, new_player_map, direction, pack_number) do
          :over ->
            # end the draft
            new_player_map
            |> Map.values()
            |> Enum.map(&text_picks/1)

            Process.exit(self(), :draftover)

          :next ->
            new_number = pack_number + 1
            new_player_map = crack_and_read_all(new_player_map, new_number)
            new_conditions = %{direction: flip(direction), pack_number: new_number}

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

    %{dm: dm, picks: picks} = Map.get(player_map, playerID)

    CardLoader.send_pack(picks, 6, dm, "picks:")
    state
  end
end
