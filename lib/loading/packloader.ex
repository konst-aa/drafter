defmodule Packloader.Server do
  use GenServer
  def start_link(loader_name) do
    loader_dir = "/Users/konstantinaa/code/elixir/drafter/loaders/" <> Atom.to_string(loader_name) <> "/"
    GenServer.start_link(__MODULE__, loader_dir, name: loader_name)
  end
  def send_cards(loader_name, dm, cards) do
    GenServer.cast(loader_name, {:send, dm, cards})
  end
  #server
  def init(loader_dir) do
    File.mkdir(loader_dir)
    {:ok, {:loading, loader_dir}}
  end
  defp size_right(path) do
    args = ["convert", "-resize", "x500", path, path]
    System.cmd("magick", args)
  end
  defp concat_rows([], _, _) do
    []
  end
  defp concat_rows(paths, loader_dir, n) do
    {row, rest} = Enum.split(paths, 5)
    concat_path = loader_dir <> "concat_" <> Integer.to_string(n) <> ".png"
    args = row ++ ["+append", concat_path]
    System.cmd("magick", args)
    [concat_path | concat_rows(rest, loader_dir, n+1)]
  end
  def handle_cast({:send, dm, cards}, {:loading, loader_dir} = state) do
    #get images
    images = cards
    |> Enum.map(fn x -> Map.get(x, :pic) end)

    #unique names and resize files
    paths = for n <- 1..length(images), do: loader_dir <> Integer.to_string(n) <> ".png"
    _written_files = List.zip([paths, images])
    |> Enum.map(fn {path, image} -> File.write(path, image) end)
    Enum.map(paths, &size_right/1) #might want to do resizing during set loading from json... will save 2 seconds... worth?

    #concat rows
    rows = concat_rows(paths, loader_dir, 0)
    finished_path = loader_dir <> "finished.png"
    args = rows ++ ["-append", finished_path]
    System.cmd("magick", args)

    #send message and clean up
    Nostrum.Api.create_message(dm.id, [file: finished_path])
    #System.cmd("rm", ["-rf", loader_dir <> "*"])
    #System.cmd("y", [])
    {:noreply, state}
  end
end
