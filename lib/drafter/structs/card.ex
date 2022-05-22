defmodule Drafter.Structs.Card do
  defstruct [:name, :set, :rarity, :color, :mc, :cmc, :type, :picURL, :pt, :pic]

  alias __MODULE__
  alias Drafter.Packloader.Server

  @type t :: %Card{
          name: String.t(),
          set: String.t(),
          rarity: String.t(),
          color: [String.t()] | [],
          mc: String.t(),
          type: String.t(),
          picURL: String.t(),
          pt: String.t(),
          pic: binary()
        }

  @type pack :: [Card.t()] | []
  @typep packs :: [pack()] | []
  @typep ghetto_card() :: map()

  @spec gen_ghetto_card(any(), any()) :: ghetto_card()
  def gen_ghetto_card([row | remainder] = _info, ghetto_card) do
    row = String.split(row, ["<", "</", ">\r", ">"])
    {[_, open_tag, contents, identifier, _], other_info} = Enum.split(row, 5)

    case identifier do
      "name" ->
        gen_ghetto_card(remainder, Map.put(ghetto_card, "name", contents))

      "manacost" ->
        gen_ghetto_card(remainder, Map.put(ghetto_card, "mc", contents))

      "cmc" ->
        gen_ghetto_card(remainder, Map.put(ghetto_card, "cmc", contents))

      "type" ->
        ghetto_card = Map.put(ghetto_card, "type", contents)

        case other_info do
          [_, pt, _, _] ->
            ghetto_card = Map.put(ghetto_card, "pt", pt)
            gen_ghetto_card(remainder, ghetto_card)

          _ ->
            gen_ghetto_card(remainder, ghetto_card)
        end

      "set" ->
        rarity_and_pic = String.split(open_tag, ["rarity=\"", "\" picURL=\"", "\""])

        ghetto_card =
          ghetto_card
          |> Map.put("set", contents)

        case rarity_and_pic do
          [_, rarity, picURL, _] ->
            ghetto_card =
              ghetto_card
              |> Map.put("rarity", rarity)
              |> Map.put("picURL", picURL)

            gen_ghetto_card(remainder, ghetto_card)

          [_, picURL, _] ->
            ghetto_card =
              ghetto_card
              |> Map.put("picURL", picURL)

            gen_ghetto_card(remainder, ghetto_card)
        end

      "color" ->
        contents = [contents | Map.get(ghetto_card, "color", [])]
        gen_ghetto_card(remainder, Map.put(ghetto_card, "color", contents))

      _ ->
        IO.puts("whoops")
        gen_ghetto_card(remainder, ghetto_card)
    end
  end

  def gen_ghetto_card(_, ghetto_card) do
    ghetto_card
  end

  @spec from_map(ghetto_card()) :: Card.t()
  def from_map(ghetto_card) do
    # convert map keys to known atom, then upload values, returning card struct
    new_map =
      ghetto_card
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    struct(Card, new_map)
  end

  @spec pull_photo(Card.t(), atom()) :: Card.t()
  defp pull_photo(%Card{picURL: picURL} = card, loader_name) do
    pic =
      picURL
      |> HTTPoison.get!()
      |> Map.get(:body)
      |> Server.resize(loader_name)

    _new_card = Map.put(card, :pic, pic)
  end

  @spec gen_packs(pack(), String.t(), integer(), atom()) :: packs()
  def gen_packs(_cards, _opt, 0, _loader_name) do
    []
  end

  def gen_packs(cards, "cube", n, loader_name) do
    {pack, rest} = Enum.split(cards, 15)
    pack = Enum.map(pack, fn card -> pull_photo(card, loader_name) end)
    [pack | gen_packs(rest, "cube", n - 1, loader_name)]
  end
end
