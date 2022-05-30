defmodule Drafter.Handler.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  alias Drafter.Pod.Registry
  alias Drafter.Loaders.SetLoader

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link do
    IO.puts("started consumer!")
    Consumer.start_link(__MODULE__)
  end

  @spec hack(Nostrum.Struct.Message.t()) :: tuple()
  defp hack(message) do
    supers = Application.fetch_env!(:drafter, :super_users)

    case String.split(message.content) do
      [command | args] ->
        %{username: username, discriminator: discriminator} = message.author

        if Enum.member?(supers, username <> "#" <> discriminator) do
          {command, args, :super}
        else
          {command, args, :notsuper}
        end

      _ ->
        {:badmessage}
    end
  end

  @spec dispatch(Nostrum.Struct.Message.t()) :: :ok | :ignore
  defp dispatch(msg) do
    case hack(msg) do
      # Super User Commands
      {"~!save", [set_name | _], :super} ->
        SetLoader.save_set(msg, set_name)

      {"~!delete", [set_name | _], :super} ->
        SetLoader.delete_set(msg.channel_id, set_name)

      {"~!killall", _, :super} ->
        Registry.kill_all(msg.channel_id)

      {"~!kill", [pod_name | _], :super} ->
        Registry.kill_pod(pod_name, msg.channel_id)

      # Regular Commands
      {"~!list", _, _} ->
        SetLoader.list_sets(msg.channel_id)

      {"~!draft", [set, option | group], _} ->
        Registry.new_pod(set, option, group, msg.channel_id)

      {"~!ready", _, _} ->
        Registry.ready_player(msg.author.id, msg.channel_id)

      {"~!pick", [index_str | _], _} ->
        Registry.pick(msg.author.id, index_str, msg.channel_id)

      {"~!picks", _, _} ->
        Registry.list_picks(msg.author.id, msg.channel_id)

      {"~!help", _, _} ->
        Api.create_message(msg.channel_id, "https://github.com/konstantin-aa/drafter-ex#commands")

      # maintenance
      {"~!ping", _, _} ->
        Api.create_message(msg.channel_id, "pong!")

      {"~!prune", _, _} ->
        Registry.prune(msg.channel_id)

      _ ->
        :ignore
    end
  end

  @spec handle_event(any()) :: atom()
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    Task.async(fn -> dispatch(msg) end)
    :ok
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end
end
