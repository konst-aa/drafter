import String
defmodule Card do
  defstruct [:name, :set, :rarity, :color, :mc, :cmc, :type, :picURL, :pt, :pic]
  def gen_ghetto_card([row | remainder] = _info, ghetto_card) do
    row = String.split(row, ["<", "</", ">\r", ">"])
    {[_, open_tag, contents, identifier, _], other_info} = Enum.split(row, 5)
    case identifier do
      "name" -> gen_ghetto_card(remainder, Map.put(ghetto_card, "name", contents))
      "manacost" -> gen_ghetto_card(remainder, Map.put(ghetto_card, "mc", contents))
      "cmc" -> gen_ghetto_card(remainder, Map.put(ghetto_card, "cmc", contents))
      "type" ->
        ghetto_card = Map.put(ghetto_card, "type", contents)
        case other_info do
          [_, pt, _, _] ->
            ghetto_card = Map.put(ghetto_card, "pt", pt)
            gen_ghetto_card(remainder, ghetto_card)
          _ -> gen_ghetto_card(remainder, ghetto_card)
        end
      "set" ->
        rarity_and_pic = String.split(open_tag, ["rarity=\"", "\" picURL=\"", "\""])
        ghetto_card = ghetto_card
        |> Map.put("set", contents)
        case rarity_and_pic do
          [_, rarity, picURL, _] ->
            ghetto_card = ghetto_card
            |> Map.put("rarity", rarity)
            |> Map.put("picURL", picURL)
            gen_ghetto_card(remainder, ghetto_card)
          [_, picURL, _] ->
            ghetto_card = ghetto_card
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
  def from_map(ghetto_card) do
    #convert map keys to known atom, then upload values, returning card struct
    new_map = ghetto_card
    |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
    |> Map.new()
    struct(Card, new_map)
  end
end
defmodule Loader do
  defp gen_ghetto_cards([]) do
    []
  end
  defp gen_ghetto_cards([row | rest] = _xml) do
    if String.contains?(row, "<card>") do
      {info, rest} = Enum.split_while(rest, fn x -> not String.contains?(x, "</card>") end)
      [Card.gen_ghetto_card(info, Map.new) | gen_ghetto_cards(rest)]
    else
      gen_ghetto_cards(rest)
    end
  end
  defp verify_new(name) do
    {:ok, sets} = File.read("./sets/sets.json")
    case JSON.decode(sets) do
      {:ok, sets} ->
        {Enum.member?(Map.keys(sets), name), sets}
      {_, reason} ->
        IO.inspect(reason)
        {:error, reason}
    end
  end
  defp unpack(xml, name) do
    xml_list = String.split(xml, "\n")
    cards = gen_ghetto_cards(xml_list)
    IO.puts("cards loaded!")
    case verify_new(name) do
      {:false, sets} ->
        {:ok, new_sets} = sets
        |> Map.put(name, cards)
        |> JSON.encode()
        File.write!("./sets/sets.json", new_sets)
        "sets loaded!"
      {:error, reason} ->
        IO.puts("error loading json")
        IO.inspect(reason)
        "error loading set"
      {_, _} -> "set already exists"
    end
  end

  def load(%{filename: filename, url: url}, name) do
    if ends_with?(filename, ".xml") do
      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{body: body}} ->
          unpack(body, name)
        {:error, reason} -> "failed loading off html #{reason}"
      end
    else
      IO.puts("no")
    end
  end
end
