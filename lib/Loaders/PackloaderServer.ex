defmodule Packloader.Server do
  use GenServer

  def start_link(loader_name) do
    loader_dir =
      "/Users/konstantinaa/code/elixir/drafter/loaders/" <> Atom.to_string(loader_name) <> "/"

    GenServer.start_link(__MODULE__, loader_dir, name: loader_name)
  end
  def resize(image, loader_name) do
    GenServer.call(loader_name, {:resize, image})
  end

  def send_cards(loader_name, dm, cards) do
    GenServer.cast(loader_name, {:send, dm, cards})
  end

  # server
  def init(loader_dir) do
    File.mkdir(loader_dir)
    {:ok, {:loading, loader_dir}}
  end

  defp name_paths(loader_dir, x) do
    for n <- 1..x, do: loader_dir <> Integer.to_string(n) <> ".png"
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
    [concat_path | concat_rows(rest, loader_dir, n + 1)]
  end

  def handle_call({:resize, image}, _from, {:loading, loader_dir} = state) do
    path = loader_dir <> "/card.png"
    File.write(path, image)
    size_right(path)
    {:reply, File.read!(path), state}
  end

  def handle_cast({:send, dm, cards}, {:loading, loader_dir} = state) do
    # get images
    images = Enum.map(cards, fn x -> Map.get(x, :pic) end)

    # unique names and resize files
    paths = name_paths(loader_dir, length(images))

    _written_files =
      List.zip([paths, images])
      |> Enum.map(fn {path, image} -> File.write(path, image) end)

    # concat rows
    rows = concat_rows(paths, loader_dir, 0)
    finished_path = loader_dir <> "finished.png"
    args = rows ++ ["-append", finished_path]
    System.cmd("magick", args)

    # send message and clean up
    Nostrum.Api.create_message(dm.id, file: finished_path)
    {:noreply, state}
  end
end
