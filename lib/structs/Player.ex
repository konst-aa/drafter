defmodule Drafter.Player do
  defstruct [:dm, :backlog, :picks, :uncracked, :left, :right]

  alias __MODULE__

  alias Drafter.Pod.Server
  alias Drafter.Card
  # alias Drafter.Packloader.Server, as: PackLoader

  @typep dm :: Nostrum.Struct.Channel.dm_channel()
  @typep dms :: [dm()] | []
  @type playerID :: integer()
  @type group :: [playerID()] | []
  @type group_strings :: [String.t()] | []
  @typep seating :: {playerID(), playerID()}
  @typep seating_list :: [seating()]
  @type t :: %__MODULE__{
          dm: dm() | nil,
          backlog: [Card.pack()] | [] | nil,
          picks: [Card.t()] | [] | nil,
          uncracked: [Card.pack()] | [] | nil,
          left: playerID() | nil,
          right: playerID() | nil
        }
  @type player_map :: %{
          Player.playerID() => Player.t()
        }
  @type card_index :: integer()
  @type card_index_string :: String.t()
  # WTF DO I DO

  @spec seating_helper(group()) :: seating_list() | []
  defp seating_helper([left_player | [me | [right_player | others]]] = _seating) do
    [{left_player, right_player} | seating_helper([me | [right_player | others]])]
  end

  defp seating_helper(_) do
    []
  end

  @spec seating(group()) :: seating_list()
  defp seating([first | _] = group) do
    group = [List.last(group) | group] ++ [first]
    seating_helper(group)
  end

  @spec group_from_strings(group_strings()) :: group()
  def group_from_strings(group_strings) do
    group_strings
    |> Enum.map(fn x -> String.trim_leading(x, "<@") |> String.trim_trailing(">") end)
    |> Enum.map(&String.to_integer/1)
  end

  # THIS SHOULD IMPORT A TYPE FROM OUTSIDE
  @spec gen_helper(dms(), Card.packs(), seating_list(), Server.option()) :: [Player.t()]
  def gen_helper([dm | rest_dms], packs, [my_seating | rest], "cube") do
    {mine, others} = Enum.split(packs, 3)
    {left, right} = my_seating

    [
      %Player{dm: dm, backlog: [], picks: [], uncracked: mine, left: left, right: right}
      | gen_helper(rest_dms, others, rest, "cube")
    ]
  end

  def gen_helper(_dms, _packs, _seating, _opt) do
    []
  end

  @spec gen_dms(group()) :: dms()
  def gen_dms([playerID | others]) do
    {:ok, snowflake_playerID} = Nostrum.Snowflake.cast(playerID)
    {:ok, dm} = Nostrum.Api.create_dm(snowflake_playerID)
    [dm | gen_dms(others)]
  end

  def gen_dms([]) do
    []
  end

  @spec gen_player_map(Server.set(), Server.option(), group(), Server.loader_name()) ::
          player_map()
  def gen_player_map(set, "cube", group, loader_name) do
    loaded_set = Enum.map(set, &Card.from_map/1)
    dms = gen_dms(group)

    for dm <- dms,
        do:
          Nostrum.Api.create_message(
            dm.id,
            "welcome, packs will be constructed soon, 5-10s per player, sry :/"
          )

    seats = seating(group)
    cards = Enum.shuffle(loaded_set)
    packs = Card.gen_packs(cards, "cube", length(group) * 3, loader_name)
    player_info = gen_helper(dms, packs, seats, "cube")

    _players =
      Enum.zip([group, player_info])
      |> Map.new()
  end

  @spec crack_pack(Player.t()) :: Player.t()
  defp crack_pack(%Player{uncracked: [pack | rest]} = player) do
    _new_player =
      player
      |> Map.put(:backlog, [pack])
      |> Map.put(:uncracked, rest)
  end

  defp crack_pack(player) do
    player
  end

  @spec crack_all(player_map()) :: player_map()
  def crack_all(player_map) do
    _new_players =
      player_map
      |> Enum.map(fn {k, v} -> {k, crack_pack(v)} end)
      |> Map.new()
  end

  @spec pull_direction(Player.t(), Server.direction()) :: playerID() | nil
  def pull_direction(player, direction) do
    case direction do
      :left -> Map.get(player, :left)
      _ -> Map.get(player, :right)
    end
  end

  # takes a card out of a pack, card_index must be an integer
  @spec pick(playerID(), card_index(), player_map()) ::
          {nil | :ok | :nopack | :outofbounds, player_map()}
  def pick(playerID, card_index, player_map) do
    player = Map.get(player_map, playerID)

    case player do
      %Player{backlog: [pack | rest_packs], picks: picks} ->
        case List.pop_at(pack, card_index) do
          {nil, _} ->
            {:outofbounds, player_map}

          {card, new_pack} ->
            player =
              player
              |> Map.put(:picks, [card] ++ picks)
              |> Map.put(:backlog, [new_pack | rest_packs])

            player_map = Map.put(player_map, playerID, player)
            {:ok, player_map}
        end

      _ ->
        {:nopack, player_map}
    end
  end

  # passes current pack in a direction
  @spec pass_pack(playerID(), Server.direction(), player_map()) :: player_map()
  def pass_pack(playerID, direction, player_map) do
    player = Map.get(player_map, playerID)
    %Player{backlog: [pack | rest_packs]} = player
    player = Map.put(player, :backlog, rest_packs)

    player_map = Map.put(player_map, playerID, player)
    targetID = pull_direction(player, direction)
    target = Map.get(player_map, targetID)
    new_target_packs = Map.get(target, :backlog) ++ [pack]
    target = Map.put(target, :backlog, new_target_packs)

    _new_player_map =
      player_map
      |> Map.put(playerID, player)
      |> Map.put(targetID, target)
  end

  @spec text_picks(Player.t()) :: {dm(), String.t()}
  def text_picks(player) do
    message =
      player
      |> Map.get(:picks)
      |> Enum.map(fn card -> Map.get(card, :name) end)
      |> Enum.join("\n")

    {Map.get(player, :dm), message}
  end
end
