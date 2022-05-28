defmodule Drafter.Pod.Registry do
  use GenServer

  alias Drafter.Pod.Server.State
  alias Drafter.Player 
  
  # API
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: :registry)
  end

  # maintenance
  @spec kill_pod(State.pod_string(), State.channelID()) :: :ok
  def kill_pod(pod_name, channelID) do
    GenServer.cast(:registry, {:kill_pod, pod_name, channelID})
  end

  @spec kill_all(State.channelID()) :: :ok
  def kill_all(channelID) do
    GenServer.cast(:registry, {:kill_all, channelID})
  end

  @spec prune(State.channelID()) :: :ok
  def prune(channelID) do
    GenServer.cast(:registry, {:prune, channelID})
  end

  # starting
  @spec new_pod(State.set(), State.option(), Player.group_strings(), State.channelID()) :: :ok
  def new_pod(set, option, group_strings, channelID) do
    GenServer.cast(:registry, {:new_pod, set, option, group_strings, channelID})
  end

  @spec ready_player(Player.playerID(), State.channelID()) :: :ok
  def ready_player(playerID, channelID) do
    GenServer.cast(:registry, {:ready_player, playerID, channelID})
  end

  # running
  @spec pick(Player.playerID(), Player.card_index_string(), State.channelID()) :: :ok
  def pick(playerID, card_index_string, channelID) do
    GenServer.cast(:registry, {:pick, playerID, card_index_string, channelID})
  end

  @spec list_picks(Player.playerID(), State.channelID()) :: :ok
  def list_picks(playerID, channelID) do
    GenServer.cast(:registry, {:list_picks, playerID, channelID})
  end

  # maintenance
  @spec handle_cast({:kill_pod, State.pod_string(), State.channelID()}, State.t()) ::
          {:noreply, State.t()}
  def handle_cast({:kill_pod, target_pod_string, channelID}, state) do
    {:noreply, State.kill_pod(state, target_pod_string, channelID)} 
  end

  @spec handle_cast({:kill_all, State.channelID()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:kill_all, channelID}, state) do
    {:noreply, State.kill_all(state, channelID)} 
  end

  @spec handle_cast({:prune, State.channelID()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:prune, channelID}, state) do
    {:noreply, State.prune(state, channelID)}
  end

  # starting
  @spec handle_cast(
          {:new_pod, State.set(), State.option(), Player.group(), State.channelID()},
          State.t()
        ) :: {:noreply, State.t()}
  def handle_cast({:new_pod, set, option, group, channelID}, state) do
    {:noreply, State.new_pod(state, set, option, group, channelID)} 
  end

  @spec handle_cast({:ready_player, Player.playerID(), State.channelID()}, State.t()) ::
          {:noreply, State.t()}
  def handle_cast({:ready_player, playerID, channelID}, state) do
    {:noreply, State.ready_player(state, playerID, channelID)}
  end

  # running
  @spec handle_cast({:pick, Player.playerID(), String.t(), State.channelID()}, State.t()) ::
          {:noreply, State.t()}
  def handle_cast({:pick, playerID, card_index_string, channelID}, state) do
    {:noreply, State.pick(state, playerID, card_index_string, channelID)} 
  end

  @spec handle_cast({:list_picks, Player.playerID(), State.channelID()}, State.t()) ::
          {:noreply, State.t()}
  def handle_cast({:list_picks, playerID, channelID}, state) do
    {:noreply, State.list_picks(state, playerID, channelID)} 
  end

  @spec handle_cast(any(), State.t()) :: {:noreply, State.t()}
  def handle_cast(_, state) do
    {:noreply, state}
  end
end
