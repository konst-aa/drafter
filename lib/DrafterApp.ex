defmodule Drafter.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HandlerSupervisor,
      Pod.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
