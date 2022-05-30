defmodule Drafter.Loaders.CardLoader do
  alias Drafter.Structs.Card
  alias Drafter.Structs.Player

  # hlc2 keeps crashing it idk why
  @spec resize(Card.pic(), integer()) :: Card.pic() | :ok
  def resize(pic, height) do
    Temp.track!()
    tmp_path = Temp.path!("cardloader-resize")
    Temp.track_file(tmp_path)
    File.write!(tmp_path, pic)

    args = ["convert", "-resize", "x" <> Integer.to_string(height), tmp_path, tmp_path]
    System.cmd("magick", args)
    out = File.read!(tmp_path)
    Temp.cleanup()
    out
  end

  @spec write_card(Card.t(), Path.t()) :: Path.t()
  defp write_card(card, path) do
    File.write!(path, Map.get(card, :pic))
    path
  end

  @spec concat([Path.t()], Path.t(), String.t()) :: Path.t()
  defp concat(card_paths, target_path, direction_arg) do
    args = card_paths ++ [direction_arg, target_path]
    System.cmd("magick", args)
    target_path
  end

  # problems: manually removes temps because the library can't automatically remove them
  # no default value if failed to find card
  @spec load_pack(Card.pack(), integer()) :: Card.pic()
  def load_pack(pack, cards_per_row) do
    Temp.track!()
    card_paths = Enum.map(pack, fn _ -> Temp.path!("cardloader-card") end)
    Enum.map(card_paths, &Temp.track_file/1)

    card_paths =
      pack
      |> Enum.zip(card_paths)
      |> Task.async_stream(fn {card, path} -> write_card(card, path) end, [{:ordered, true}])
      |> Enum.map(fn {_, v} -> v end)
      # group by row
      |> Enum.chunk_every(cards_per_row)

    row_paths = Enum.map(card_paths, fn _ -> Temp.path!("cardloader-row") end)
    Enum.map(row_paths, &Temp.track_file/1)

    row_paths =
      card_paths
      |> Enum.zip(row_paths)
      |> Task.async_stream(fn {row, path} -> concat(row, path, "+append") end)
      |> Enum.map(fn {_, v} -> v end)

    pack_path = Temp.path!("cardloader-pack")
    Temp.track_file(pack_path)
    concat(row_paths, pack_path, "-append")

    out = File.read!(pack_path)
    # this shouldn't be here if i didn't need to manually clean up
    Temp.cleanup()
    out
  end

  @spec send_pack(Card.pack(), integer(), Player.dm(), String.t()) :: :ok
  def send_pack(pack, cards_per_row, dm, message) do
    Temp.track!()
    loaded_pack = load_pack(pack, cards_per_row)
    # <> ".png"
    loaded_pack_path = Temp.path!(%{prefix: "cardloader-sender", suffix: ".png"})
    Temp.track_file(loaded_pack_path)
    File.write!(loaded_pack_path, loaded_pack)
    Nostrum.Api.create_message(dm.id, %{content: message, file: loaded_pack_path})
    Temp.cleanup()
    :ok
  end
end
