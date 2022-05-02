defmodule Drafter.Pod.Server do
  use GenServer

  alias Drafter.Player
  alias Drafter.Packloader

  @type pod_name :: atom()
  @type pod_string :: String.t()

  @type set :: String.t()
  @type option :: String.t()
  @type channelID :: Nostrum.Struct.Channel.id()
  @type pod_pid :: pid()
  @type loader_name :: atom()

  @typep pack_number :: integer()
  @typep direction :: :left | :right
  @typep conditions :: %{direction: direction(), pack_number: pack_number()}
  @typep waiting_group :: %{Player.playerID() => boolean()} | %{}
  @typep waiting_state ::
           {:waiting,
            %{
              set: set(),
              option: option(),
              group: waiting_group()
            }}
  @typep running_state ::
           {:running,
            %{
              loader_name: loader_name(),
              option: option(),
              player_map: Player.player_map(),
              conditions: conditions()
            }
            | %{}}
  @typep state :: running_state() | waiting_state()

  @spec start_link(pod_name(), any()) :: GenServer.on_start()
  def start_link(pod_name, state) do
    GenServer.start_link(__MODULE__, state, name: pod_name)
  end

  # waiting
  @spec ready(pod_name(), Player.playerID(), channelID()) :: :ok
  def ready(pod_name, playerID, channelID) do
    GenServer.cast(pod_name, {:ready, pod_name, playerID, channelID})
  end

  # running
  @spec pick(pod_name(), Player.playerID(), Player.card_index_string() | Player.card_index()) ::
          :ok
  def pick(pod_name, playerID, card_index) do
    # needs to pass channelID probably
    GenServer.cast(pod_name, {:pick, playerID, card_index})
  end

  @spec picks(pod_name(), Player.playerID()) :: :ok
  def picks(pod_name, playerID) do
    GenServer.cast(pod_name, {:picks, playerID})
  end

  # helpers
  # waiting
  @spec mint_loader_name(pod_name()) :: loader_name()
  defp mint_loader_name(pod_name) do
    number =
      pod_name
      |> Atom.to_string()
      |> String.trim_leading("pod-")

    _loader_name = String.to_atom("loader-" <> number)
  end

  # running
  @spec read_cur_pack(loader_name(), Player.t(), pack_number()) :: :ok
  defp read_cur_pack(loader_name, %Player{dm: dm, backlog: backlog} = _player, pack_number) do
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

  @spec gen_running_state(pod_name(), waiting_state()) ::
          running_state() | {:reply, :nullset, {%{}, %{}}}
  defp gen_running_state(pod_name, {:waiting, state_map}) do
    %{set: set, option: option, group: group} = state_map
    contents = File.read!("./sets/sets.json")
    sets = JSON.decode!(contents)
    IO.puts("starting")

    case Map.get(sets, set, :undefined) do
      :undefined ->
        {:reply, :nullset, {Map.new(), Map.new()}}

      set ->
        # link the loader
        loader_name = mint_loader_name(pod_name)
        {:ok, _loader_pid} = Packloader.Server.start_link(loader_name)

        # make the player_map
        player_map = Player.gen_player_map(set, option, Map.keys(group), loader_name)

        # crack the packs
        pack_number = 1
        player_map = crack_and_read_all(loader_name, player_map, pack_number)

        # celebrate
        IO.puts("player_map generated, draft started")
        conditions = %{direction: :left, pack_number: pack_number}

        {:running,
         %{
           loader_name: loader_name,
           option: option,
           player_map: player_map,
           conditions: conditions
         }}
    end
  end

  # running
  @spec flip(:right) :: :left
  defp flip(:right), do: :left
  @spec flip(:left) :: :right
  defp flip(:left), do: :right

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
  @spec init({set(), option(), Player.group()}) :: {:ok, waiting_state()}
  def init({set, option, group}) do
    falses = for _player <- group, do: false
    {:ok, {:waiting, %{set: set, option: option, group: Map.new(Enum.zip([group, falses]))}}}
  end

  @spec handle_cast({:ready, pod_name(), Player.playerID(), channelID()}, waiting_state()) ::
          {:noreply, state()}
  def handle_cast({:ready, pod_name, playerID, channelID}, {:waiting, state_map}) do
    %{set: set, option: option, group: group} = state_map
    group = Map.put(group, playerID, true)
    vals = Map.values(group)

    if vals == for(_val <- vals, do: true) do
      {:noreply, gen_running_state(pod_name, {:waiting, state_map})}
    else
      Nostrum.Api.create_message(channelID, "verified!")
      {:noreply, {:waiting, state_map}}
    end
  end

  # running state
  @spec handle_cast({:pick, Player.playerID(), Player.card_index()}, running_state()) ::
          {:noreply, running_state()} | true
  def handle_cast({:pick, playerID, card_index}, {:running, state_map}) do
    %{player_map: player_map, loader_name: loader_name, option: option, conditions: conditions} =
      state_map

    case Player.pick(playerID, card_index, player_map) do
      {:outofbounds, _} ->
        # send messages
        {:noreply, {:running, state_map}}

      {:nopack, _} ->
        # send messages
        {:noreply, {:running, state_map}}

      {:ok, new_players} ->
        %{direction: direction, pack_number: pack_number} = conditions
        new_players = Player.pass_pack(playerID, direction, new_players)

        case passed_messages(loader_name, playerID, new_players, direction, pack_number) do
          :over ->
            # end the draft
            new_players
            |> Enum.map(fn {_id, player} -> Player.text_picks(player) end)
            |> Enum.map(fn {dm, msg} ->
              Nostrum.Api.create_message(dm.id, "draft over, picks: \n" <> msg)
            end)

            Process.exit(self(), :draftover)

          :next ->
            new_number = pack_number + 1
            new_players = crack_and_read_all(loader_name, new_players, new_number)

            new_conditions = %{direction: flip(direction), pack_number: new_number}

            {:noreply,
             {:running,
              %{
                loader_name: loader_name,
                option: option,
                player_maps: new_players,
                conditions: new_conditions
              }}}

          :passed ->
            {:noreply,
             {:running,
              %{
                loader_name: loader_name,
                option: option,
                player_maps: new_players,
                conditions: conditions
              }}}
        end
    end
  end

  @spec handle_cast({:picks, Player.playerID()}, running_state()) :: {:noreply, running_state()}
  def handle_cast({:picks, playerID}, {:running, state_map}) do
    %{player_map: player_map} = state_map

    {dm, msg} =
      player_map
      |> Map.get(playerID)
      |> Player.text_picks()

    Nostrum.Api.create_message(dm.id, msg)
    {:noreply, {:running, state_map}}
  end

  @spec handle_cast(any(), any()) :: {:noreply, :ignore}
  def handle_cast(_, _) do
    {:noreply, :ignore}
  end

  # any state
  @spec handle_call(:state, {pid(), any()}, state()) :: {:reply, state(), state()}
  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end

  @spec handle_call(any(), {pid(), any()}, state()) :: {:reply, String.t(), state()}
  def handle_call(_, _from, state) do
    {:reply, "not the time!", state}
  end
end
