defmodule Drafter.Loaders.CardLoaderTest do
  use ExUnit.Case, async: true

  alias Drafter.Loaders.CardLoader
  alias Drafter.Structs.Card

  # I have no idea why the image binaries kept ending up different,
  # I guess I can't rely on imagemagick to make *exactly* the same images
  # I think this is a good eyeball of the dimensions being the same
  @spec image_length(binary()) :: integer()
  def image_length(image) do
    image
    |> :binary.bin_to_list()
    |> length()
  end

  setup do
    mock_files = "./test/mock-files/"

    [pic, resized_pic, pack_pic, ghetto_card] =
      [
        mock_files <> "whale_visions_pic.png",
        mock_files <> "whale_visions_resized_pic.png",
        mock_files <> "whale_visions_pack.png",
        mock_files <> "whale_visions.json"
      ]
      |> Enum.map(&File.read!/1)

    mock_card =
      ghetto_card
      |> JSON.decode!()
      |> Card.from_map()
      |> Map.put(:pic, resized_pic)

    %{
      pic: pic,
      mock_card: mock_card,
      resized_pic: resized_pic,
      loaded_pack: pack_pic
    }
  end

  test "picture is resized properly", context do
    %{pic: pic, resized_pic: expected_resized} = context
    resized_pic = CardLoader.resize(pic, 500)
    assert image_length(resized_pic) == image_length(expected_resized)
  end

  test "rows of whales visions are concatenated", context do
    %{mock_card: mock_card, loaded_pack: expected_pack} = context
    mock_pack = List.duplicate(mock_card, 15)

    loaded_pack = CardLoader.load_pack(mock_pack, 5)

    assert image_length(loaded_pack) == image_length(expected_pack)
  end
end
