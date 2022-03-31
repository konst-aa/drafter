defmodule HandlerConsumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  def start_link do
    IO.puts("started consumer!")
    Consumer.start_link(__MODULE__)
  end

  defp hack(message) do
    case String.split(message) do
      [command | args] -> {command, args}
      _ -> []
    end
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case hack(msg.content) do
      {"!ping", _args} ->
        Api.create_message(msg.channel_id, "pyongyang!")

      {"!load", [name]} ->
        case msg.attachments do
          [set | _tail] ->
            Api.create_message(msg.channel_id, "loading set...")
            output_msg = SetLoader.load(set, name)
            Api.create_message(msg.channel_id, output_msg)

          _ ->
            IO.puts("no attachment!")
        end
        #needs to be done on A DIFFERENT THREAD !!!!

      {"!draft", [set | [option | group]]} ->
        Pod.Registry.new_pod(set, option, group, msg.channel_id)

      {"!ready", _} ->
        Pod.Registry.ready_player(msg.author.id, msg.channel_id)

      {"!killall", _} ->
        Pod.Registry.kill_all(msg.channel_id)

      {"!kill", [pod_name | _]} ->
        Pod.Registry.kill_pod(pod_name, msg.channel_id)

      {"!prune", _} ->
        Pod.Registry.prune(msg.channel_id)

      {"!pick", [index_str | _]} ->
        Pod.Registry.pick(msg.author.id, index_str, msg.channel_id)

      {"!picks", _} ->
        Pod.Registry.picks(msg.author.id, msg.channel_id)

      _ ->
        :ignore
    end
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end
end
