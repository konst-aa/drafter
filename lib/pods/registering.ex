defmodule Pod.Registry do
  use GenServer
  #API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: :registry)
  end
  def whereis_name(pod_name) do
    GenServer.call(:registry, {:whereis_name, pod_name})
  end
  def whereis_player(player) do
    GenServer.call(:registry, {:whereis_player, player})
  end
  def verify_group(group) do
    GenServer.call(:registry, {:verify_group, group})
  end
  def register_name(pod_name, group, pid) do
    GenServer.call(:registry, {:register_name, pod_name, group, pid})
  end

  def unregister_name(pod_name) do
    GenServer.cast(:registry, {:unregister_name, pod_name})
  end

  def kill_pod(pod) do
    case GenServer.call(:registry, {:kill_pod, pod}) do
      :ok -> "pod killed"
      _ -> "not an existing pod"
    end
  end
  def kill_all() do
    GenServer.call(:registry, {:kill_all})
  end
  defp first_free(keys, n) do
    test = "pod-#{n}"
    test = String.to_atom(test)
    unless Enum.member?(keys, test) do
      test
    else
      first_free(keys, n+1)
    end
  end
  def new_pod({set, option, group}) do
    {_, pods} = GenServer.call(:registry, {:state})
    pod_atom = first_free(Map.keys(pods), 0)
    group = group
    |> Enum.map(fn x -> String.trim_leading(x, "<@!") |> String.trim_trailing(">")end)
    |> Enum.map(&String.to_integer/1)
    case whereis_name(pod_atom) do
      :undefined ->
        if verify_group(group) do
          {:ok, pid} = Pod.Server.start_link(pod_atom, {set, option, group})
          register_name(pod_atom, group, pid)
          "pod registered with name -> " <> Atom.to_string(pod_atom)
        else
          "someone is already in a pod!"
        end
      _pid ->
        "pod with such a name already exists"
    end
  end

  def ready_player(player) do
    pod = whereis_player(player)
    case whereis_name(pod) do
      :undefined ->
        "pod doesn't exist, or you're not in a pod"
      _pid ->
        IO.puts("here we go")
        case Pod.Server.ready(pod, player) do
          :nullset ->
            kill_pod(pod)
            "no such set exists"
          message ->
            message
        end
    end
  end
  def pick(playerID, index) do
    case whereis_player(playerID) do
      :undefined -> "you're not in a pod"
      pod_name ->
        Pod.Server.pick(pod_name, playerID, index)
    end
  end
  def picks(playerID) do
    case whereis_player(playerID) do
      :undefined -> "you're not in a pod"
      pod_name ->
        Pod.Server.picks(pod_name, playerID)
    end
  end
  #server
  def init(_) do
    IO.puts("started!")
    {:ok, {Map.new, Map.new}}
  end
  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end
  def handle_call({:whereis_player, player}, _from, {players, pods}) do
    {:reply, Map.get(players, player, :undefined), {players, pods}}
  end
  def handle_call({:verify_group, group}, _from, {players, pods}) do
    {:reply, not Enum.any?(Map.keys(players), fn x -> x in group end), {players, pods}}
  end
  def handle_call({:whereis_name, pod_name}, _from, {players, pods}) do
    {:reply, Map.get(pods, pod_name, :undefined), {players, pods}}
  end

  def handle_call({:register_name, pod_name, group, pid}, _from, {players, pods}) do
    case Map.get(pods, pod_name) do
      nil ->
        pod_name_repeated = for _member <- group, do: pod_name
        new_players = Map.new(Enum.zip([group, pod_name_repeated]))
        {:reply, :yes, {Map.merge(players, new_players), Map.put(pods, pod_name, pid)}}
      _ ->
        {:reply, :no, {players, pods}}
    end
  end

  def handle_call({:kill_pod, target_pod}, _from, {players, pods}) do
    case Map.get(pods, target_pod, :undefined) do
      :undefined -> {:reply, :nopod, {players, pods}}
      pid ->
        Process.exit(pid, :killed)
        new_players = Map.filter(players, fn {_player, pod} -> pod != target_pod end)
        new_pods = Map.delete(pods, target_pod)
        {:reply, :ok, {new_players, new_pods}}
    end
  end
  def handle_call({:kill_all}, _from, {_players, pods}) do
    for pod <- Map.values(pods), do: Process.exit(pod, :killed)
    {:reply, "all pods killed!", {Map.new, Map.new}}
  end
end
