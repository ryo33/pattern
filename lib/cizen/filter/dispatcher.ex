defmodule Cizen.Filter.Dispatcher do
  @moduledoc """
  A Dispather for `Cizen.Filter`.
  """

  alias Cizen.Filter
  alias Cizen.Filter.Dispatcher.Node

  use GenServer

  @spec start_link([GenServer.option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec put(GenServer.server(), Filter.t(), any) :: :ok
  def put(name, filter, ref) do
    GenServer.cast(name, {:put, filter, ref})
  end

  @spec delete(GenServer.server(), Filter.t(), any) :: :ok
  def delete(name, filter, ref) do
    GenServer.cast(name, {:delete, filter, ref})
  end

  @spec dispatch(GenServer.server(), any) :: [any]
  def dispatch(name, event) do
    node = GenServer.call(name, :get)

    node
    |> Node.get(event)
    |> MapSet.to_list()
  end

  @impl GenServer
  def init(_) do
    {:ok, Node.new()}
  end

  @impl GenServer
  def handle_cast({:put, filter, ref}, state) do
    {:noreply, Node.put(state, filter.code, ref)}
  end

  @impl GenServer
  def handle_cast({:delete, filter, ref}, state) do
    {:noreply, Node.delete(state, filter.code, ref)}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end
end
