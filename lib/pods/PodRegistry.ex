defmodule Drafter.Pod.Registry do
  use GenServer
  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: :registry)
  end

  # maintenance
  def kill_pod(pod, channelID) do
    GenServer.cast(:registry, {:kill_pod, pod, channelID})
  end

  def kill_all(channelID) do
    GenServer.cast(:registry, {:kill_all, channelID})
  end

  def prune(channelID) do
    GenServer.cast(:registry, {:prune, channelID})
  end

  # starting
  def new_pod(set, option, group, channelID) do
    GenServer.cast(:registry, {:new_pod, set, option, group, channelID})
  end

  def ready_player(player, channelID) do
    GenServer.cast(:registry, {:ready_player, player, channelID})
  end

  # running
  def pick(playerID, index, channelID) do
    GenServer.cast(:registry, {:pick, playerID, index, channelID})
  end

  def picks(playerID, channelID) do
    GenServer.cast(:registry, {:picks, playerID, channelID})
  end

  # helpers
  # registry stuff
  defp whereis_pod(pod_name, {_players, pods} = _state) do
    Map.get(pods, pod_name, :undefined)
  end

  defp whereis_player(player, {players, _pods} = _state) do
    Map.get(players, player, :undefined)
  end

  defp register_name(pod_name, group, pid, {players, pods}) do
    pod_name_repeated = for _member <- group, do: pod_name
    new_players = Map.new(Enum.zip([group, pod_name_repeated]))
    {Map.merge(players, new_players), Map.put(pods, pod_name, pid)}
  end

  defp first_free(keys, n) do
    test = String.to_atom("pod-#{n}")

    unless Enum.member?(keys, test) do
      test
    else
      first_free(keys, n + 1)
    end
  end

  defp pruned({players, pods} = _state) do
    dead_pods =
      pods
      |> Enum.reject(fn {_, v} -> Process.alive?(v) end)
      |> Enum.map(fn {k, _} -> k end)

    pods = Map.drop(pods, dead_pods)
    pod_keys = Map.keys(pods)

    players = Map.filter(players, fn {_, v} -> v in pod_keys end)
    {players, pods}
  end

  # starting
  defp verify_group(group, {players, _pods}) do
    not Enum.any?(Map.keys(players), fn x -> x in group end)
  end

  @spec group_from_strings([String.t()]) :: [integer()]
  defp group_from_strings(group) do
    group
    |> Enum.map(fn x -> String.trim_leading(x, "<@!") |> String.trim_trailing(">") end)
    |> Enum.map(&String.to_integer/1)
  end

  # server
  def init(_) do
    IO.puts("started!")
    {:ok, {Map.new(), Map.new()}}
  end

  # maintenance
  def handle_cast({:kill_pod, target_pod, channelID}, {_players, pods} = state) do
    target_pod = String.to_existing_atom(target_pod)

    case Map.get(pods, target_pod, :undefined) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "no pod with such a name")
        {:noreply, pruned(state)}

      pid ->
        Process.exit(pid, :killed)
        Nostrum.Api.create_message(channelID, "pod killed!")
        {:noreply, pruned(state)}
    end
  end

  def handle_cast({:kill_all, channelID}, {_players, pods} = _state) do
    for pod <- Map.values(pods), do: Process.exit(pod, :killed)
    Nostrum.Api.create_message(channelID, "all pods killed!")
    {:noreply, {Map.new(), Map.new()}}
  end

  def handle_cast({:prune, channelID}, state) do
    Nostrum.Api.create_message(channelID, "pods pruned!")
    {:noreply, pruned(state)}
  end

  # starting
  def handle_cast({:new_pod, set, option, group, channelID}, {_players, pods} = state) do
    pod_atom = first_free(Map.keys(pods), 0)

    group = group_from_strings(group)

    case whereis_pod(pod_atom, state) do
      :undefined ->
        if verify_group(group, state) do
          {:ok, pid} = Pod.Server.start_link(pod_atom, {set, option, group})
          msg = "pod registered with name -> " <> Atom.to_string(pod_atom)
          Nostrum.Api.create_message(channelID, msg)
          {:noreply, register_name(pod_atom, group, pid, pruned(state))}
        else
          Nostrum.Api.create_message(channelID, "someone is already in a pod!")
          {:noreply, pruned(state)}
        end

      _pid ->
        Nostrum.Api.create_message(channelID, "pod with such a name already exists")
        {:noreply, pruned(state)}
    end
  end

  def handle_cast({:ready_player, player, channelID}, state) do
    pod = whereis_player(player, pruned(state))

    case whereis_pod(pod, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")
        {:noreply, pruned(state)}

      _pid ->
        Pod.Server.ready(pod, player, channelID)
        {:noreply, pruned(state)}
    end
  end

  # running
  def handle_cast({:pick, playerID, index_str, channelID}, state) do
    case Integer.parse(index_str) do
      :error ->
        Nostrum.Api.create_message(channelID, "invalid index")
        {:noreply, pruned(state)}

      {index, _} ->
        case whereis_player(playerID, state) do
          :undefined ->
            Nostrum.Api.create_message(channelID, "you're not in a pod")
            {:noreply, pruned(state)}

          pod_name ->
            Pod.Server.pick(pod_name, playerID, index)
            {:noreply, pruned(state)}
        end
    end
  end

  def handle_cast({:picks, playerID, channelID}, state) do
    case whereis_player(playerID, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")

      pod_name ->
        Pod.Server.picks(pod_name, playerID)
        {:noreply, state}
    end
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end
end
