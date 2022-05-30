defmodule Drafter.Structs.Card do
  defstruct [:name, :set, :rarity, :color, :mc, :cmc, :type, :picURL, :pt, :pic]

  alias __MODULE__
  alias Drafter.Loaders.CardLoader

  @type pic :: binary()
  @type t :: %Card{
          name: String.t() | nil,
          set: String.t() | nil,
          rarity: String.t() | nil,
          color: [String.t()] | [] | nil,
          mc: String.t() | nil,
          cmc: String.t() | nil,
          type: String.t() | nil,
          picURL: String.t() | nil,
          pt: String.t() | nil,
          pic: pic() | nil
        }

  @type pack :: [Card.t()] | []
  @typep packs :: [pack()] | []
  @type ghetto_card() :: map()

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
      # handle failing to get
      |> HTTPoison.get!()
      |> Map.get(:body)
      |> CardLoader.resize(500)

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
end
