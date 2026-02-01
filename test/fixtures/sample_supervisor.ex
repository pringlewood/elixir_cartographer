defmodule SampleApp.Application do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    children = [
      {SampleApp.Workers.CacheServer, []},
      {SampleApp.Workers.TaskRunner, []},
      {Phoenix.PubSub, name: SampleApp.PubSub}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
