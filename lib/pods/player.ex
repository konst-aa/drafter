defmodule Pack do
  defp pull_photo(card) do
    pic = card
    |> Map.get(:picURL)
    |> HTTPoison.get!()
    |> Map.get(:body)
    _new_card = Map.put(card, :pic, pic)
  end
  def gen_packs(_cards, _opt, 0) do
    []
  end
  def gen_packs(cards, "cube", n) do
    {pack, rest} = Enum.split(cards, 3)
    pack = Enum.map(pack, &pull_photo/1)
    [pack | gen_packs(rest, "cube", n-1)]
  end
end
defmodule Player do
  defstruct [:dm, :backlog, :picks, :uncracked, :left, :right]
  defp seating_helper([left_player | [me | [right_player | others]]] = _seating) do
    [{left_player, right_player} | seating_helper([me | [right_player | others]])]
  end
  defp seating_helper(_) do
    []
  end
  defp seating([first |_] = players) do
    players = [List.last(players) | players] ++ [first]
    seating_helper(players)
  end
  def gen_helper([dm | rest_dms] = _dms ,packs, [my_seating | rest] = _seating, "cube") do
    {mine, others} = Enum.split(packs, 3)
    {left, right} = my_seating
    [%Player{dm: dm, backlog: [], picks: [], uncracked: mine, left: left, right: right} | gen_helper(rest_dms, others, rest, "cube")]
  end
  def gen_helper(_dms,_packs, _seating, _opt) do
    []
  end
  def gen_dms([player | others] = _players) do
    {:ok, player_id} = Nostrum.Snowflake.cast(player)
    {:ok, dm} = Nostrum.Api.create_dm(player_id)
    [dm | gen_dms(others)]
  end
  def gen_dms([]) do
    []
  end
  def gen_players(set, "cube", group) do
    IO.puts("generating players...")
    IO.inspect(group)
    dms = gen_dms(group)
    for dm <- dms, do: Nostrum.Api.create_message(dm.id, "welcome, packs will be constructed soon!")
    seats = seating(group)
    #IO.puts("seaeting")
    #IO.inspect(seats)
    IO.puts("dms")
    IO.inspect(dms)
    cards = Enum.shuffle(set)
    packs = Pack.gen_packs(cards, "cube", length(group) * 3)
    player_info = gen_helper(dms, packs, seats, "cube")
    _players = Enum.zip([group, player_info])
    |> Map.new()
    |> IO.inspect()
  end
  defp crack_pack(%Player{uncracked: [pack | rest]} = player) do
    _new_player = player
    |> Map.put(:backlog, [pack])
    |> Map.put(:uncracked, rest)
  end
  defp crack_pack(player) do
    player
  end
  def crack_all(players) do
    _new_players = players
    |> Enum.map(fn {k, v} -> {k, crack_pack(v)} end)
    |> Map.new()
  end
  def pull_direction(player, direction) do
    case direction do
      :left -> Map.get(player, :left)
      _ -> Map.get(player, :right)
    end
  end
  def pick(playerID, card_index, players) do #takes a card out of a pack, card_index must be an integer
    player = Map.get(players, playerID)
    case player do
      %Player{backlog: [pack | rest_packs], picks: picks} ->
        case List.pop_at(pack, card_index) do
          {:nil, _} ->
            {:outofbounds, players}
          {card, new_pack} ->
            player = player
            |> Map.put(:picks, [card] ++ picks)
            |> Map.put(:backlog, [new_pack | rest_packs])
            players = Map.put(players, playerID, player)
            {:ok, players}
        end
      _ -> {:nopack, players}
    end
  end
  def pass_pack(playerID, direction, players) do #passes current pack in a direction
    player = Map.get(players, playerID)
    %Player{backlog: [pack | rest_packs]} = player
    player = Map.put(player, :backlog, rest_packs)

    players = Map.put(players, playerID, player)
    targetID = pull_direction(player, direction)
    target = Map.get(players, targetID)
    new_target_packs = Map.get(target, :backlog) ++ [pack]
    target = Map.put(target, :backlog, new_target_packs)

    _new_players = players
    |> Map.put(playerID, player)
    |> Map.put(targetID, target)
  end
  def text_picks(player) do
    message = player
    |> Map.get(:picks)
    |> Enum.map(fn card -> Map.get(card, :name) end)
    |> Enum.join("\n")
    {Map.get(player, :dm), message}
  end
end
