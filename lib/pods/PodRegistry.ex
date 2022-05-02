defmodule Drafter.Pod.Registry do
  use GenServer

  alias Drafter.Pod.Server
  alias Drafter.Player

  # API
  @typep player_locations ::
           %{
             Player.playerID() => Server.pod_name()
           }
           | %{}
  @typep pods ::
           %{
             Server.pod_name() => Server.pod_pid()
           }
           | %{}
  @typep state :: %{
           locations: player_locations(),
           pods: pods()
         }

  # API
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: :registry)
  end

  # maintenance
  @spec kill_pod(Server.pod_string(), Server.channelID()) :: :ok
  def kill_pod(pod_name, channelID) do
    GenServer.cast(:registry, {:kill_pod, pod_name, channelID})
  end

  @spec kill_all(Server.channelID()) :: :ok
  def kill_all(channelID) do
    GenServer.cast(:registry, {:kill_all, channelID})
  end

  @spec prune(Server.channelID()) :: :ok
  def prune(channelID) do
    GenServer.cast(:registry, {:prune, channelID})
  end

  # starting
  @spec new_pod(Server.set(), Server.option(), Player.group_strings(), Server.channelID()) :: :ok
  def new_pod(set, option, group_strings, channelID) do
    GenServer.cast(:registry, {:new_pod, set, option, group_strings, channelID})
  end

  @spec ready_player(Player.playerID(), Server.channelID()) :: :ok
  def ready_player(playerID, channelID) do
    GenServer.cast(:registry, {:ready_player, playerID, channelID})
  end

  # running
  @spec pick(Player.playerID(), Player.card_index_string(), Server.channelID()) :: :ok
  def pick(playerID, card_index_string, channelID) do
    GenServer.cast(:registry, {:pick, playerID, card_index_string, channelID})
  end

  @spec picks(Player.playerID(), Server.channelID()) :: :ok
  def picks(playerID, channelID) do
    GenServer.cast(:registry, {:picks, playerID, channelID})
  end

  # helpers
  # registry stuff
  @spec whereis_pod(Server.pod_name(), state()) :: Server.pod_pid() | :undefined
  defp whereis_pod(pod_name, %{pods: pods}) do
    Map.get(pods, pod_name, :undefined)
  end

  @spec whereis_player(Player.playerID(), state()) :: Server.pod_name() | :undefined
  defp whereis_player(playerID, %{locations: locations}) do
    Map.get(locations, playerID, :undefined)
  end

  @spec register_name(Server.pod_name(), Player.group(), Server.pod_pid(), state()) :: state()
  defp register_name(pod_name, group, pod_pid, %{locations: locations, pods: pods}) do
    pod_name_repeated = for _member <- group, do: pod_name
    new_locations = Map.new(Enum.zip([group, pod_name_repeated]))
    %{locations: Map.merge(locations, new_locations), pods: Map.put(pods, pod_name, pod_pid)}
  end

  @spec first_free([Server.pod_name()], integer()) :: Server.pod_name()
  defp first_free(pod_names, n) do
    test = String.to_atom("pod-#{n}")

    unless Enum.member?(pod_names, test) do
      test
    else
      first_free(pod_names, n + 1)
    end
  end

  @spec pruned(state()) :: state()
  defp pruned(%{locations: locations, pods: pods}) do
    # gets rid of dead stuff
    dead_pods =
      pods
      |> Enum.reject(fn {_, v} -> Process.alive?(v) end)
      |> Enum.map(fn {k, _} -> k end)

    new_pods = Map.drop(pods, dead_pods)
    pod_keys = Map.keys(pods)

    new_locations = Map.filter(locations, fn {_, v} -> v in pod_keys end)
    %{locations: new_locations, pods: new_pods}
  end

  # starting
  @spec verify_group(Player.group(), state()) :: boolean()
  defp verify_group(group, %{locations: locations}) do
    not Enum.any?(Map.keys(locations), fn x -> x in group end)
  end

  # server
  @spec init(any()) :: {:ok, state()}
  def init(_) do
    IO.puts("started!")
    {:ok, %{locations: Map.new(), pods: Map.new()}}
  end

  # maintenance
  @spec handle_cast({:kill_pod, Server.pod_string(), Server.channelID()}, state()) ::
          {:noreply, state()}
  def handle_cast({:kill_pod, target_pod_string, channelID}, %{pods: pods} = state) do
    target_pod = String.to_existing_atom(target_pod_string)

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

  @spec handle_cast({:kill_all, Server.channelID()}, state()) :: {:noreply, state()}
  def handle_cast({:kill_all, channelID}, {_players, pods} = _state) do
    for pod <- Map.values(pods), do: Process.exit(pod, :killed)
    Nostrum.Api.create_message(channelID, "all pods killed!")
    {:noreply, %{locations: Map.new(), pods: Map.new()}}
  end

  @spec handle_cast({:prune, Server.channelID()}, state()) :: {:noreply, state()}
  def handle_cast({:prune, channelID}, state) do
    Nostrum.Api.create_message(channelID, "pods pruned!")
    {:noreply, pruned(state)}
  end

  # starting
  @spec handle_cast(
          {:new_pod, Server.set(), Server.option(), Player.group(), Server.channelID()},
          state()
        ) :: {:noreply, state()}
  def handle_cast({:new_pod, set, option, group, channelID}, %{pods: pods} = state) do
    pod_atom = first_free(Map.keys(pods), 0)

    group = Player.group_from_strings(group)

    case whereis_pod(pod_atom, state) do
      :undefined ->
        if verify_group(group, state) do
          {:ok, pid} = Server.start_link(pod_atom, {set, option, group})
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

  @spec handle_cast({:ready_player, Player.playerID(), Server.channelID()}, state()) ::
          {:noreply, state()}
  def handle_cast({:ready_player, playerID, channelID}, state) do
    pod_name = whereis_player(playerID, pruned(state))

    case whereis_pod(pod_name, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")
        {:noreply, pruned(state)}

      _pid ->
        Server.ready(pod_name, playerID, channelID)
        {:noreply, pruned(state)}
    end
  end

  # running
  @spec handle_cast({:pick, Player.playerID(), String.t(), Server.channelID()}, state()) ::
          {:noreply, state()}
  def handle_cast({:pick, playerID, card_index_string, channelID}, state) do
    case Integer.parse(card_index_string) do
      :error ->
        Nostrum.Api.create_message(channelID, "invalid index")
        {:noreply, pruned(state)}

      {index, _} ->
        case whereis_player(playerID, state) do
          :undefined ->
            Nostrum.Api.create_message(channelID, "you're not in a pod")
            {:noreply, pruned(state)}

          pod_name ->
            Server.pick(pod_name, playerID, index)
            {:noreply, pruned(state)}
        end
    end
  end

  @spec handle_cast({:picks, Player.playerID(), Server.channelID()}, state()) ::
          {:noreply, state()}
  def handle_cast({:picks, playerID, channelID}, state) do
    case whereis_player(playerID, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")

      pod_name ->
        Server.picks(pod_name, playerID)
        {:noreply, state}
    end
  end

  @spec handle_cast(any(), state()) :: {:noreply, state()}
  def handle_cast(_, state) do
    {:noreply, state}
  end
end
