defmodule Drafter.Structs.CardTest do
  use ExUnit.Case, async: true
  
  alias Drafter.Structs.Card

  setup do
    whale_visions_ghetto = "./whale_visions.json"
                           |> File.read!()
                           |> JSON.decode!()
    %{mock_ghetto_card: whale_visions_ghetto, #literally just the same mock card
      mock_card: 1, #mock card
      mock_set: "wtf"#mock the set???
    }
  end

  test "ghetto card is made properly into a struct", context do
    
  end

  test "packs are generated correctly", context do
    
  end
end
