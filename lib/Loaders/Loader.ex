defmodule Drafter.SetLoader do
  defp gen_ghetto_cards([]) do
    []
  end

  # WTF IS THIS FUNCTION DOING HERE figure out setloading FFS
  defp gen_ghetto_cards([row | rest] = _xml) do
    if String.contains?(row, "<card>") do
      {info, rest} = Enum.split_while(rest, fn x -> not String.contains?(x, "</card>") end)
      [Card.gen_ghetto_card(info, Map.new()) | gen_ghetto_cards(rest)]
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
      {false, sets} ->
        {:ok, new_sets} =
          sets
          |> Map.put(name, cards)
          |> JSON.encode()

        File.write!("./sets/sets.json", new_sets)
        "sets loaded!"

      {:error, reason} ->
        IO.puts("error loading json")
        IO.inspect(reason)
        "error loading set"

      {_, _} ->
        "set already exists"
    end
  end

  def load(%{filename: filename, url: url}, name) do
    if String.ends_with?(filename, ".xml") do
      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{body: body}} ->
          unpack(body, name)

        {:error, reason} ->
          "failed loading off html #{reason}"
      end
    else
      IO.puts("no")
    end
  end
end
