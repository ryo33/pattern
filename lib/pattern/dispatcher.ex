defmodule Pattern.Dispatcher do
  @moduledoc """
  A Dispather for `Pattern`.
  """

  alias Pattern
  alias Pattern.Dispatcher.Node

  use GenServer

  @spec start_link([GenServer.option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec put(GenServer.server(), Pattern.t(), any) :: :ok
  def put(name, pattern, ref) do
    GenServer.cast(name, {:put, pattern, ref})
  end

  @spec delete(GenServer.server(), Pattern.t(), any) :: :ok
  def delete(name, pattern, ref) do
    GenServer.cast(name, {:delete, pattern, ref})
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
  def handle_cast({:put, pattern, ref}, state) do
    {:noreply, Node.put(state, pattern.code, ref)}
  end

  @impl GenServer
  def handle_cast({:delete, pattern, ref}, state) do
    {:noreply, Node.delete(state, pattern.code, ref)}
  end

  @impl GenServer
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end
end
