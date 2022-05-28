defmodule Drafter.MixProject do
  use Mix.Project

  def project do
    [
      app: :drafter,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_options: [debug_info: Mix.env() == :dev],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:nostrum, :httpoison, :json],
      mod: {Drafter.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostrum, "~> 0.5.1"},
      {:httpoison, "~> 1.8.0"},
      {:json, "~> 1.4"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
