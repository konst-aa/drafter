defmodule Drafter.Loaders.CardLoaderTest do
  use ExUnit.Case, async: true
  
  alias Drafter.Loaders.CardLoader

  setup do
    [pic, resized_pic] = ["./whale_visions_pic", "whale_visions_resized_pic"]
                         |> Enum.map(&File.read!/1)
    %{pic: pic, resized_pic: resized_pic}
  end

  test "picture is resized properly", context do 
    %{pic: pic, resized_pic: resized_pic} = context
    IO.inspect(pic)
    assert CardLoader.resize(pic, 500) == resized_pic
  end
end
