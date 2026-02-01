defmodule SampleApp.Workers.CacheServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, %{cache: %{}, ttl: Keyword.get(opts, :ttl, 60_000)}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.cache, key), state}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    {:noreply, %{state | cache: Map.put(state.cache, key, value)}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    {:noreply, %{state | cache: %{}}}
  end
end
