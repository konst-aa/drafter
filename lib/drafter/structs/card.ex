defmodule Drafter.Structs.Card do
  defstruct [:name, :set, :rarity, :color, :mc, :cmc, :type, :picURL, :pt, :pic]

  alias __MODULE__
  alias Drafter.Loaders.CardLoader
  
  @type pic :: binary()
  @type t :: %Card{
          name: String.t(),
          set: String.t(),
          rarity: String.t(),
          color: [String.t()] | [],
          mc: String.t(),
          type: String.t(),
          picURL: String.t(),
          pt: String.t(),
          pic: pic()
        }

  @type pack :: [Card.t()] | []
  @typep packs :: [pack()] | []
  @typep ghetto_card() :: map()

  @spec from_map(ghetto_card()) :: Card.t()
  def from_map(ghetto_card) do
    # convert map keys to known atom, then upload values, returning card struct
    new_map =
      ghetto_card
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    struct(Card, new_map)
  end

  @spec pull_photo(Card.t()) :: Card.t()
  defp pull_photo(%Card{picURL: picURL} = card) do
    pic =
      picURL
      |> HTTPoison.get!() #handle failing to get
      |> Map.get(:body)
      |> CardLoader.resize()
    _new_card = Map.put(card, :pic, pic)
  end

  @spec gen_packs([Card.t()], String.t(), integer()) :: packs()
  def gen_packs(_cards, _opt, 0) do
    []
  end
  
  def gen_packs(cards, "cube", n) do
    {pack, rest} = Enum.split(cards, 15)
    pack = Enum.map(pack, fn card -> pull_photo(card) end)
    [pack | gen_packs(rest, "cube", n - 1)]
  end

