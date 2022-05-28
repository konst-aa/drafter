defmodule Drafter.Pod.Registry.State do
  defstruct [:locations, :pods]

  alias Drafter.Player
  alias Drafter.Pod.Server

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
  @type t :: %__MODULE__{
           locations: player_locations(),
           pods: pods()
         }

  # helpers
  # registry stuff
  @spec whereis_pod(Server.pod_name(), t()) :: Server.pod_pid() | :undefined
  defp whereis_pod(pod_name, %{pods: pods}) do
    Map.get(pods, pod_name, :undefined)
  end

  @spec whereis_player(Player.playerID(), t()) :: Server.pod_name() | :undefined
  defp whereis_player(playerID, %{locations: locations}) do
    Map.get(locations, playerID, :undefined)
  end

  @spec register_name(Server.pod_name(), Player.group(), Server.pod_pid(), t()) :: t()
  defp register_name(pod_name, group, pod_pid, %{locations: locations, pods: pods}) do
    pod_name_repeated = List.duplicate(pod_name, List.length(group))
    new_locations = Map.new(Enum.zip([group, pod_name_repeated]))
    %__MODULE__{locations: Map.merge(locations, new_locations), pods: Map.put(pods, pod_name, pod_pid)}
  end

  @spec first_free([Server.pod_name()], integer()) :: Server.pod_name()
  defp first_free(pod_names, n) do
    attempt  = String.to_atom("pod-#{n}")

    unless Enum.member?(pod_names, test) do
      attempt
    else
      first_free(pod_names, n + 1)
    end
  end

  @spec pruned(t()) :: t()
  defp pruned(%{locations: locations, pods: pods}) do
    # gets rid of dead stuff
    dead_pods =
      pods
      |> Enum.reject(fn {_, v} -> Process.alive?(v) end)
      |> Enum.map(fn {k, _} -> k end)

    new_pods = Map.drop(pods, dead_pods)
    pod_keys = Map.keys(pods)

    new_locations = Map.filter(locations, fn {_, v} -> v in pod_keys end)
    %__MODULE__{locations: new_locations, pods: new_pods}
  end

  # starting
  @spec verify_group(Player.group(), t()) :: boolean()
  defp verify_group(group, %{locations: locations}) do
    not Enum.any?(Map.keys(locations), fn x -> x in group end)
  end

  # maintenance
  @spec kill_pod(t(), Server.pod_string(), Server.channelID()) :: t()
  def kill_pod(%{pods: pods} = state, target_pod_string, channelID) do
    target_pod = String.to_existing_atom(target_pod_string)
    
    case Map.get(pods, target_pod, :undefined) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "no pod with such a name")

      pid ->
        Process.exit(pid, :killed)
        Nostrum.Api.create_message(channelID, "pod killed!")
    end
    pruned(state)
  end

  @spec kill_all(t(), Server.channelID()) :: t()
  def kill_all({_players, pods} = _state, channelID) do
    for pod <- Map.values(pods), do: Process.exit(pod, :killed)
    Nostrum.Api.create_message(channelID, "all pods killed!")
    %__MODULE__{locations: Map.new(), pods: Map.new()}
  end

  @spec prune(t(), Server.channelID()) :: t()
  def prune(state, channelID) do
    Nostrum.Api.create_message(channelID, "pods pruned!")
    pruned(state)
  end

  # starting
  @spec new_pod(t(), Server.set(), Server.option(), Player.group(), Server.channelID()) :: t()
  def new_pod(%{pods: pods} = state, set, option, group, channelID) do
    pod_atom = first_free(Map.keys(pods), 0)

    group = Player.group_from_strings(group)

    case whereis_pod(pod_atom, state) do
      :undefined ->
        if verify_group(group, state) do
          {:ok, pid} = Server.start_link(pod_atom, {set, option, group})
          msg = "pod registered with name -> " <> Atom.to_string(pod_atom)
          Nostrum.Api.create_message(channelID, msg)
          pruned(register_name(pod_atom, group, pid, pruned(state)))
        else
          Nostrum.Api.create_message(channelID, "someone is already in a pod!")
          pruned(state)
        end

      _pid ->
        Nostrum.Api.create_message(channelID, "pod with such a name already exists")
        pruned(state)
    end
  end

  @spec ready_player(t(), Player.playerID(), Server.channelID()) :: t()
  def ready_player(state, playerID, channelID) do
    pod_name = whereis_player(playerID, pruned(state))

    case whereis_pod(pod_name, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")

      _pid ->
        Server.ready(pod_name, playerID, channelID)
    end
    pruned(state)
  end

  # running
  @spec pick(t(),Player.playerID(), String.t(), Server.channelID()) :: t()
  def pick(state, playerID, card_index_string, channelID) do
    case Integer.parse(card_index_string) do
      :error ->
        Nostrum.Api.create_message(channelID, "invalid index")

      {index, _} ->
        case whereis_player(playerID, state) do
          :undefined ->
            Nostrum.Api.create_message(channelID, "you're not in a pod")

          pod_name ->
            Server.pick(pod_name, playerID, index)

        end
    end
    pruned(state)
  end

  @spec list_picks(t(), Player.playerID(), Server.channelID()) :: t()
  def list_picks(state, playerID, channelID) do
    case whereis_player(playerID, state) do
      :undefined ->
        Nostrum.Api.create_message(channelID, "you're not in a pod")

      pod_name ->
        Server.picks(pod_name, playerID)
    end
    pruned(state)
  end
end
