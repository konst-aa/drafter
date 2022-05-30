defmodule Drafter.Structs.CardTest do
  use ExUnit.Case, async: true

  alias Drafter.Structs.Card

  setup do
    mock_files = "./test/mock-files/"

    [whale_visions_ghetto] =
      [mock_files <> "whale_visions.json"]
      |> Enum.map(&File.read!/1)

    # literally just the same mock card#mock card
    %{
      mock_ghetto_card: JSON.decode!(whale_visions_ghetto),
      # mock the set???
      mock_set: "wtf"
    }
  end

  test "ghetto card is made properly into a struct", context do
    %{mock_ghetto_card: ghetto_card} = context

    assert %Card{} = Card.from_map(ghetto_card)
  end

  test "packs are generated correctly", context do
  end
end
