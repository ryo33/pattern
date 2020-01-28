defmodule Cizen.Filter.DispatcherTest do
  use ExUnit.Case

  alias Cizen.Event
  alias Cizen.Filter
  alias Cizen.Filter.Dispatcher
  require Filter

  defmodule(Event, do: defstruct([:body]))
  defmodule(TestEventA, do: defstruct([]))
  defmodule(TestEventB, do: defstruct([]))
  defmodule(TestEventC, do: defstruct([]))

  setup do
    {:ok, pid} = Dispatcher.start_link()
    {:ok, pid: pid}
  end

  test "returns empty dispatch for no subscriptions", %{pid: pid} do
    assert [] == Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
  end

  test "returns matched dispatch", %{pid: pid} do
    Dispatcher.put(pid, Filter.new(fn %Event{body: %TestEventA{}} -> true end), 1)
    Dispatcher.put(pid, Filter.new(fn %Event{body: %TestEventB{}} -> true end), 2)
    assert [1] == Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert [2] == Dispatcher.dispatch(pid, %Event{body: %TestEventB{}})
    assert [] == Dispatcher.dispatch(pid, %Event{body: %TestEventC{}})
  end

  test "returns multiple matched dispatch", %{pid: pid} do
    Dispatcher.put(pid, Filter.new(fn %Event{body: %TestEventA{}} -> true end), 1)
    Dispatcher.put(pid, Filter.new(fn %Event{body: %TestEventA{}} -> true end), 2)
    Dispatcher.put(pid, Filter.new(fn %Event{body: %TestEventB{}} -> true end), 3)
    dispatch = Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert MapSet.new([1, 2]) == MapSet.new(dispatch)
  end

  test "deletes subscription", %{pid: pid} do
    filter_1 = Filter.new(fn %Event{body: %TestEventA{}} -> true end)
    filter_2 = Filter.new(fn %Event{body: %TestEventA{}} -> true end)
    filter_3 = Filter.new(fn %Event{body: %TestEventB{}} -> true end)
    Dispatcher.put(pid, filter_1, 1)
    Dispatcher.put(pid, filter_2, 2)
    Dispatcher.put(pid, filter_3, 3)
    Dispatcher.delete(pid, filter_2, 2)
    Dispatcher.delete(pid, filter_3, 3)
    assert [1] == Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert [] == Dispatcher.dispatch(pid, %Event{body: %TestEventB{}})
  end
end
