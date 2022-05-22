defmodule Drafter.Application do
  use Application

  @impl true

  @spec start(any, any) :: {:error, any} | {:ok, pid}
  def start(_type, _args) do
    children = [
      Drafter.Handler.Supervisor,
      Drafter.Pod.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
