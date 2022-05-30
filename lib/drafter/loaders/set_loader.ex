defmodule Drafter.Loaders.SetLoader do
  use GenServer

  alias Drafter.Loaders.SetLoader.State

  @impl true
  @spec init([State.t()]) :: {:ok, State.t()}
  def init([set_folder]) do
    IO.puts("set loader up! with folder:")
    IO.inspect(set_folder)
    {:ok, set_folder}
  end

  @spec start_link(State.t()) :: GenServer.on_start()
  def start_link(set_folder) do
    GenServer.start_link(__MODULE__, set_folder, name: :set_loader)
  end

  @spec load_set(State.set_name()) :: State.load_set_return()
  def load_set(set_name) do
    GenServer.call(:set_loader, {:load_set, set_name})
  end

  @spec list_sets(State.channelID()) :: :ok
  def list_sets(channelID) do
    GenServer.cast(:set_loader, {:list_sets, channelID})
  end

  @spec delete_set(State.channelID(), State.set_name()) :: :ok
  def delete_set(channelID, set_name) do
    GenServer.cast(:set_loader, {:delete_set, channelID, set_name})
  end

  @spec save_set(State.message(), State.set_name()) :: :ok
  def save_set(message_with_set, set_name) do
    GenServer.cast(:set_loader, {:save_set, message_with_set, set_name})
  end

  @spec write_set(State.message(), State.set_name(), State.set_list()) :: :ok
  def write_set(message_with_set, set_name, set_list) do
    GenServer.cast(:set_loader, {:write_set, message_with_set, set_name, set_list})
  end

  # doesn't send out messages
  @spec handle_call(any(), any(), State.t()) :: {:reply, any(), State.t()}
  @impl true
  def handle_call({:load_set, set_name}, _anyone, set_folder) do
    {:reply, State.load_set(set_folder, set_name), set_folder}
  end

  # does send out messages
  @spec handle_cast(any(), State.t()) :: {:noreply, State.t()}
  @impl true
  def handle_cast({:list_sets, channelID}, set_folder) do
    {:noreply, State.list_sets(set_folder, channelID)}
  end

  def handle_cast({:delete_set, channelID, set_name}, set_folder) do
    {:noreply, State.delete_set(set_folder, channelID, set_name)}
  end

  # unpacking the set is expensive, but writing the set is the only time for errors
  # therefore it makes no sense to clog up the server while unpacking the set
  def handle_cast({:save_set, message_with_set, set_name}, set_folder) do
    {:noreply, State.save_set(set_folder, message_with_set, set_name)}
  end

  def handle_cast({:write_set, message_with_set, set_name, set_list}, set_folder) do
    {:noreply, State.write_set(set_folder, message_with_set, set_name, set_list)}
  end
end
