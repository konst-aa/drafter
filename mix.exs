defmodule Drafter.MixProject do
  use Mix.Project

  def project do
    [
      app: :drafter,
      version: "0.1.0",
      elixir: "~> 1.13",
      # elixirc_options: [debug_info: Mix.env() == :dev],
      # start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:nostrum, :httpoison, :json, :temp, :sweet_xml],
      mod: {Drafter.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git"},
      {:httpoison, "~> 1.8.0"},
      {:temp, git: "https://github.com/danhper/elixir-temp"},
      {:sweet_xml, "~> 0.7.1"},
      {:json, "~> 1.4"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end
end
