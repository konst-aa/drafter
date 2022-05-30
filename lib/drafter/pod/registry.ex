defmodule Drafter.Pod.Registry do
  use GenServer

  alias Drafter.Pod.Server
  alias Drafter.Player
  alias Drafter.Pod.Registry

  # API
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: :registry)
  end

  # maintenance
  @spec init(any()) :: {:ok, Registry.State.t()}
  @impl true
  def init(_args) do
    {:ok, %Registry.State{locations: Map.new(), pods: Map.new()}}
  end

  @spec kill_pod(Server.State.pod_string(), Server.State.channelID()) :: :ok
  def kill_pod(pod_name, channelID) do
    GenServer.cast(:registry, {:kill_pod, pod_name, channelID})
  end

  @spec kill_all(Server.State.channelID()) :: :ok
  def kill_all(channelID) do
    GenServer.cast(:registry, {:kill_all, channelID})
  end

  @spec prune(Server.State.channelID()) :: :ok
  def prune(channelID) do
    GenServer.cast(:registry, {:prune, channelID})
  end

  # starting
  @spec new_pod(
          Server.State.set(),
          Server.State.option(),
          Player.group_strings(),
          Server.State.channelID()
        ) :: :ok
  def new_pod(set, option, group_strings, channelID) do
    GenServer.cast(:registry, {:new_pod, set, option, group_strings, channelID})
  end

  @spec ready_player(Player.playerID(), Server.State.channelID()) :: :ok
  def ready_player(playerID, channelID) do
    GenServer.cast(:registry, {:ready_player, playerID, channelID})
  end

  # running
  @spec pick(Player.playerID(), Player.card_index_string(), Server.State.channelID()) :: :ok
  def pick(playerID, card_index_string, channelID) do
    GenServer.cast(:registry, {:pick, playerID, card_index_string, channelID})
  end

  @spec list_picks(Player.playerID(), Server.State.channelID()) :: :ok
  def list_picks(playerID, channelID) do
    GenServer.cast(:registry, {:list_picks, playerID, channelID})
  end

  # maintenance
  @impl true
  @spec handle_cast(any(), Registry.State.t()) :: {:noreply, Registry.State.t()}
  def handle_cast({:kill_pod, target_pod_string, channelID}, state) do
    {:noreply, Registry.State.kill_pod(state, target_pod_string, channelID)}
  end

  def handle_cast({:kill_all, channelID}, state) do
    {:noreply, Registry.State.kill_all(state, channelID)}
  end

  def handle_cast({:prune, channelID}, state) do
    {:noreply, Registry.State.prune(state, channelID)}
  end

  # starting
  def handle_cast({:new_pod, set, option, group, channelID}, state) do
    {:noreply, Registry.State.new_pod(state, set, option, group, channelID)}
  end

  def handle_cast({:ready_player, playerID, channelID}, state) do
    {:noreply, Registry.State.ready_player(state, playerID, channelID)}
  end

  # running
  def handle_cast({:pick, playerID, card_index_string, channelID}, state) do
    {:noreply, Registry.State.pick(state, playerID, card_index_string, channelID)}
  end

  def handle_cast({:list_picks, playerID, channelID}, state) do
    {:noreply, Registry.State.list_picks(state, playerID, channelID)}
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end
end
