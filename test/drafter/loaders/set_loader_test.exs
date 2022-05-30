defmodule Drafter.Loaders.SetLoaderTest do
  use ExUnit.Case, async: true

  alias Drafter.Loaders.SetLoader

  setup do
    mock_files = "./test/mock-files/"

    [set_xml, expected_json] =
      [
        mock_files <> "minihellscube.xml",
        mock_files <> "minihellscube.json"
      ]
      |> Enum.map(&File.read!/1)

    %{
      set_xml: set_xml,
      expected_json: expected_json
    }
  end

  test "properly turns an xml into a map", context do
    %{set_xml: set_xml, expected_json: expected_json} = context
    assert SetLoader.State.unpack(set_xml) == JSON.decode!(expected_json)
  end
end
