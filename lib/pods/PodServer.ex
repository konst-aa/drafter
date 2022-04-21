defmodule Drafter.Pod.Server do
  use GenServer

  alias Drafter.Player

  @type pod_name :: atom()

  @type set :: String.t()
  @type option :: String.t()
  @type group :: [Player.playerID()]

  @typep loader_name :: atom()
  @typep conditions :: %{direction: :left | :right, pack_number: int()}
  @typep waiting_state ::
           {:waiting,
            %{
              set: set(),
              option: option(),
              group: group()
            }}
  @typep running_state ::
           {:running,
            %{
              loader_name: loader_name(),
              option: option(),
              players: PodRegistry.players(),
              conditions: conditions()
            }}

  @spec start_link(pod_name, any()) :: GenServer.on_start()
  def start_link(pod_name, state) do
    GenServer.start_link(__MODULE__, state, name: pod_name)
  end

  # waiting
  def ready(pod_name, player, channelID) do
    GenServer.cast(pod_name, {:ready, pod_name, player, channelID})
  end

  # running
  def pick(pod_name, playerID, index) do
    # needs to pass channelID probably
    GenServer.cast(pod_name, {:pick, playerID, index})
  end

  def picks(pod_name, playerID) do
    GenServer.cast(pod_name, {:picks, playerID})
  end

  # helpers
  # waiting
  defp mint_loader_name(pod_name) do
    number =
      pod_name
      |> Atom.to_string()
      |> String.trim_leading("pod-")

    _loader_name = String.to_atom("loader-" <> number)
  end

  # running
  defp read_cur_pack(loader_name, %Player{dm: dm, backlog: backlog} = _player, pack_number) do
    [pack | _] = backlog
    content = "pack #{pack_number} pick #{16 - length(pack)}"
    Nostrum.Api.create_message(dm.id, content)
    Packloader.Server.send_cards(loader_name, dm, pack)
  end

  defp crack_and_read_all(loader_name, players, pack_number) do
    new_players = Player.crack_all(players)
    Enum.map(new_players, fn {_, player} -> read_cur_pack(loader_name, player, pack_number) end)
    new_players
  end

  defp gen_running_state(pod_name, {:waiting, set, option, group}) do
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

        # make the players
        set = Enum.map(set, &Card.from_map/1)
        players = Player.gen_players(set, option, Map.keys(group), loader_name)

        # crack the packs
        pack_number = 1
        players = crack_and_read_all(loader_name, players, pack_number)

        # celebrate
        IO.puts("players generated, draft started")
        {:running, loader_name, option, players, {:left, pack_number}}
    end
  end

  defp flip(:right), do: :left
  defp flip(:left), do: :right

  defp passed_messages(loader_name, playerID, players, direction, pack_number) do
    crack? =
      players
      |> Map.values()
      |> Enum.map(fn x -> Map.get(x, :backlog) end)
      |> Enum.all?(fn backlog -> backlog == [[]] end)

    unless crack? do
      player = Map.get(players, playerID)
      targetID = Player.pull_direction(player, direction)
      target = Map.get(players, targetID)

      case player do
        %Player{backlog: [[] | _]} -> nil
        %Player{backlog: [_pack | _]} -> read_cur_pack(loader_name, player, pack_number)
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
  # waiting state
  def init({set, option, group}) do
    falses = for _player <- group, do: false
    {:ok, {:waiting, set, option, Map.new(Enum.zip([group, falses]))}}
  end

  def handle_cast({:ready, pod_name, player, channelID}, {:waiting, set, option, group} = state) do
    group = Map.put(group, player, true)
    vals = Map.values(group)

    if vals == for(_val <- vals, do: true) do
      {:noreply, gen_running_state(pod_name, state)}
    else
      Nostrum.Api.create_message(channelID, "verified!")
      {:noreply, {:waiting, set, option, group}}
    end
  end

  # running state
  def handle_cast(
        {:pick, playerID, index},
        {:running, loader_name, option, players, draft_info} = state
      ) do
    case Player.pick(playerID, index, players) do
      {:outofbounds, _} ->
        # send messages
        {:noreply, state}

      {:nopack, _} ->
        # send messages
        {:noreply, state}

      {:ok, new_players} ->
        {direction, pack_number} = draft_info
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

            new_info = {flip(direction), new_number}
            {:noreply, {:running, loader_name, option, new_players, new_info}}

          :passed ->
            {:noreply, {:running, loader_name, option, new_players, draft_info}}
        end
    end
  end

  def handle_cast({:picks, playerID}, {:running, _, _, players, _} = state) do
    {dm, msg} =
      players
      |> Map.get(playerID)
      |> Player.text_picks()

    Nostrum.Api.create_message(dm.id, msg)
    {:noreply, state}
  end

  def handle_cast(_, _) do
    {:noreply, :ignore}
  end

  # any state
  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end

  def handle_call(_, _from, state) do
    {:reply, "not the time!", state}
  end
end
