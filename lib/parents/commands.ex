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
            output_msg = Loader.load(set, name)
            Api.create_message(msg.channel_id, output_msg)
          _ ->
            IO.puts("no attachment!")
        end
      {"!draft", [set | [option | group]]} ->
        Api.create_message(msg.channel_id, Pod.Registry.new_pod({set, option, group}))
      {"!ready", _} ->
        Api.create_message(msg.channel_id, Pod.Registry.ready_player(msg.author.id))
      {"!killall", _} ->
        Api.create_message(msg.channel_id, Pod.Registry.kill_all())
      {"!kill", [pod_name | _]} ->
        Api.create_message(msg.channel_id, Pod.Registry.kill_pod(String.to_existing_atom(pod_name)))
      {"!pick", [card_index | _]} ->
        case Integer.parse(card_index) do
          :error -> Api.create_message(msg.channel_id, "invalid index")
          {index, _} ->
            Pod.Registry.pick(msg.author.id, index)
        end
      {"!picks", _} ->
        Pod.Registry.picks(msg.author.id)
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
