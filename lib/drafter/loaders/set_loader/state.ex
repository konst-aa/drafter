defmodule Drafter.Loaders.SetLoader.State do
  import SweetXml
  alias Drafter.Structs.Card
  alias Drafter.Loaders.SetLoader

  @type t :: Path.t()
  @type set_name :: String.t()
  @type channelID :: Nostrum.Struct.Channel.id()
  @type message :: Nostrum.Struct.Message.t()
  @type load_set_return :: {:ok, [Card.ghetto_card()]} | {:error, atom()}
  @type set_list :: [%{String.t() => String.t()}]

  @spec unpacker(message(), set_name()) :: :ok
  defp unpacker(
         %{attachments: [%{filename: filename, url: url}], channel_id: channelID} =
           message_with_set,
         set_name
       ) do
    unless String.contains?(set_name, "/") do
      if String.ends_with?(filename, ".xml") do
        case HTTPoison.get(url) do
          {:ok, %HTTPoison.Response{body: body}} ->
            SetLoader.write_set(message_with_set, set_name, unpack(body))

          {:error, reason} ->
            Nostrum.Api.create_message!(channelID, "failed loading off html #{reason}")
        end
      else
        Nostrum.Api.create_message!(channelID, "not xml")
      end
    else
      Nostrum.Api.create_message!(channelID, "come on!")
    end

    :ok
  end

  defp unpacker(message_without_set, _) do
    Nostrum.Api.create_message!(message_without_set.channel_id, "you need 1 attachment")
    :ok
  end

  @spec unpack(binary()) :: set_list()
  def unpack(set_xml) do
    set_xml
    |> parse(dtd: :none)
    |> xpath(
      ~x"//cards/card"l,
      name: ~x"./name/text()"o,
      set: ~x"./set/text()"o,
      rarity: ~x"./set/@rarity"o,
      color: ~x"./color/text()"lo,
      mc: ~x"./manacost/text()"o,
      cmc: ~x"./cmc/text()"o,
      type: ~x"./type/text()"o,
      picURL: ~x"./set/@picURL"o,
      pt: ~x"./pt/text()"o
    )
    |> Enum.map(fn card ->
      card
      |> Enum.filter(fn {_, v} -> v != nil end)
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), List.to_string(v)} end)
      |> Map.new()
    end)
  end

  @spec load_set(t(), set_name()) :: load_set_return()
  def load_set(set_folder, set_name) do
    case File.read(set_folder <> set_name <> ".json") do
      {:ok, set_binary} -> {:ok, JSON.decode!(set_binary)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_sets(t(), channelID()) :: t()
  def list_sets(set_folder, channelID) do
    {listed_sets, _} = System.cmd("ls", [set_folder])
    Nostrum.Api.create_message!(channelID, listed_sets)
    set_folder
  end

  @spec delete_set(t(), channelID(), set_name()) :: t()
  def delete_set(set_folder, channelID, set_name) do
    unless String.contains?(set_name, "/") do
      {out, _} = System.cmd("rm", [set_folder <> set_name <> ".json"])
      Nostrum.Api.create_message!(channelID, out)
    else
      Nostrum.Api.create_message!(channelID, "come on!")
    end

    set_folder
  end

  # parsing is better done asynchronously to not clog up the loader
  @spec save_set(t(), message(), set_name()) :: t()
  def save_set(set_folder, message_with_set, set_name) do
    Task.start(fn -> unpacker(message_with_set, set_name) end)
    set_folder
  end

  # actually writes the set
  @spec write_set(t(), message(), set_name(), set_list()) :: t()
  def write_set(set_folder, message_with_set, set_name, set_list) do
    IO.inspect(set_folder)
    set_path = set_folder <> set_name <> ".json"
    System.cmd("rm", [set_path])
    File.write!(set_path, JSON.encode!(set_list))
    Nostrum.Api.create_message(message_with_set.channel_id, "set written!")
    set_folder
  end
end
