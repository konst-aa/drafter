defmodule Drafter.Handler.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  alias Drafter.Pod.Registry

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link do
    IO.puts("started consumer!")
    Consumer.start_link(__MODULE__)
  end

  @spec hack(Nostrum.Struct.Message.t()) :: tuple()
  defp hack(message) do
    case String.split(message.content) do
      [command | args] -> {command, args}
      _ -> {:badmessage}
    end
  end

  @spec dispatch(Nostrum.Struct.Message.t()) :: :ok | :ignore
  defp dispatch(msg) do
    case hack(msg) do
      {"!ping", _args} ->
        Api.create_message(msg.channel_id, "pyongyang!")

      # i am literally going to rewrite all of load
      {"!load", [name]} ->
        case msg.attachments do
          [set | _tail] ->
            Api.create_message(msg.channel_id, "loading set...")
            output_msg = SetLoader.load(set, name)
            Api.create_message(msg.channel_id, output_msg)
            :ok

          _ ->
            IO.puts("no attachment!")
            :ok
        end

      # needs to be done on A DIFFERENT THREAD !!!!

      {"!draft", [set | [option | group]]} ->
        Registry.new_pod(set, option, group, msg.channel_id)

      {"!ready", _} ->
        Registry.ready_player(msg.author.id, msg.channel_id)

      {"!killall", _} ->
        Registry.kill_all(msg.channel_id)

      {"!kill", [pod_name | _]} ->
        Registry.kill_pod(pod_name, msg.channel_id)

      {"!prune", _} ->
        Registry.prune(msg.channel_id)

      {"!pick", [index_str | _]} ->
        Registry.pick(msg.author.id, index_str, msg.channel_id)

      {"!picks", _} ->
        Registry.picks(msg.author.id, msg.channel_id)

      _ ->
        :ignore
    end
  end

  @spec handle_event(Nostrum.Consumer.message_create()) :: :ok
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    Task.async(fn -> dispatch(msg) end)
    :ok
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  @spec handle_event(any()) :: :noop
  def handle_event(_event) do
    :noop
  end
end
