defmodule Pod.Server do
  use GenServer
  def start_link(pod_name, state) do
    GenServer.start_link(__MODULE__, state, name: pod_name)
  end

  #waiting
  def ready(pod_name, player) do
    GenServer.call(pod_name, {:ready, pod_name, player}, :infinity)
  end

  #running
  def pick(pod_name, playerID, index) do
    GenServer.cast(pod_name, {:pick, playerID, index})
  end

  def picks(pod_name, playerID) do
    GenServer.cast(pod_name, {:picks, playerID})
  end
  #any
  def state(pod_name) do
    GenServer.call(pod_name, {:state})
  end

  #server
  #waiting state
  def init({set, option, group}) do
    falses = for _player <- group, do: :false
    {:ok,  {:waiting, set, option, Map.new(Enum.zip([group, falses]))}}
  end
  defp mint_loader_name(pod_name) do
    number = pod_name
    |> Atom.to_string()
    |> String.trim_leading("pod-")
    _loader_name = String.to_atom("loader-" <> number)
  end
  defp read_cur_pack(loader_name, %Player{dm: dm, backlog: backlog} = _player, pack_number) do
    [pack | _] = backlog
    content = "pack #{pack_number} pick #{16 - length(pack)}"
    Nostrum.Api.create_message(dm.id, content)
    Packloader.Server.send_cards(loader_name, dm, pack)
  end
  defp gen_big_state(pod_name, {:waiting, set, option, group}) do
    contents = File.read!("./sets/sets.json")
    sets = JSON.decode!(contents)
    case Map.get(sets, set, :undefined) do
      :undefined -> {:reply, :nullset, {Map.new, Map.new}}
      set ->
        #link the loader
        loader_name = mint_loader_name(pod_name)
        {:ok, _loader_pid} = Packloader.Server.start_link(loader_name)

        #make the players
        set = Enum.map(set, &Card.from_map()/1)
        players = Player.gen_players(set, "cube", Map.keys(group))
        |> Player.crack_all()

        #crack the packs
        pack_number = 1
        Enum.map(players, fn {_, player} -> read_cur_pack(loader_name, player, pack_number) end)

        #celebrate
        IO.puts("players generated, draft started")
        {:reply, "draft started!", {:running, loader_name, option, players, {:left, pack_number}}}
    end
  end

  def handle_call({:ready, pod_name, player}, _from, {:waiting, set, option, group}) do
    if Enum.member?(Map.keys(group), player) do
      group = Map.put(group, player, :true)
      vals = Map.values(group)
      if vals == (for _val <- vals, do: :true) do
        IO.inspect(group)
        gen_big_state(pod_name, {:waiting, set, option, group})
      else
        {:reply, "verified!", {:waiting, set, option, group}}
      end
    else
      {:reply, "#{player} is not part of the draft!", {set, option, group}}
    end
  end

  #running state

  #any state
  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end
  def handle_call(_, _from, state) do
    {:reply, "not the time!", state}
  end
  defp passed_messages(loader_name, playerID, players, direction, pack_number) do
    crack? = players
    |> Map.values()
    |> Enum.map(fn x -> Map.get(x, :backlog) end)
    |> Enum.all?(fn backlog -> backlog == [[]] end)
    unless crack? do
      player = Map.get(players, playerID)
      targetID = Player.pull_direction(player, direction)
      target = Map.get(players, targetID)

      case player do
        %Player{backlog: [[] | _]} -> :nil
        %Player{backlog: [_pack | _]} -> read_cur_pack(loader_name, player, pack_number)
        _ -> :nil
      end
      case target do
        %Player{backlog: [[] | _]} -> :nil
        %Player{backlog: [_pack | []]} -> read_cur_pack(loader_name, target, pack_number)
        _ -> :nil
      end
      :passed
    else
      IO.inspect("crack!")
      unless pack_number == 3 do
        #crack next pack
        :next
      else
        #draft over
        :over
      end
    end
  end
  defp flip(:right), do: :left
  defp flip(:left), do: :right
  def handle_cast({:pick, playerID, index}, {:running, loader_name, option, players, {direction, pack_number}= _draft_info} = state) do
    case Player.pick(playerID, index, players) do
      {:outofbounds, _} ->
        #send messages
        {:noreply, state}
      {:nopack, _} ->
        #send messages
        {:noreply, state}
      {:ok, new_players} ->
        new_players = Player.pass_pack(playerID, direction, new_players)
        case passed_messages(loader_name, playerID, new_players, direction, pack_number) do
          :over ->
            #end the draft
            new_players
            |> Enum.map(fn {_id, player} -> Player.text_picks(player) end)
            |> Enum.map(fn {dm, msg} -> Nostrum.Api.create_message(dm.id, "draft over, picks: \n" <>  msg) end)
            Process.exit(self(), :draftover)
          :next ->
            new_players = Player.crack_all(new_players)
            Enum.map(new_players, fn {_, player} -> read_cur_pack(loader_name, player, pack_number + 1) end)
            {:noreply, {:running, loader_name, option, new_players, {flip(direction), pack_number + 1}}}
          :passed ->
            {:noreply, {:running, loader_name, option, new_players, {direction, pack_number}}}
        end
    end
  end
  def handle_cast({:picks, playerID}, {:running, _, _, players, _} = state) do
    {dm, msg} = players
    |> Map.get(playerID)
    |> Player.text_picks()
    Nostrum.Api.create_message(dm.id, msg)
    {:noreply, state}
  end
  def handle_cast(_, state) do
    {:noreply, state}
  end
end
