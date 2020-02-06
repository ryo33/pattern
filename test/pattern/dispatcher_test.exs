defmodule Pattern.DispatcherTest do
  use ExUnit.Case

  alias Cizen.Event
  alias Pattern
  alias Pattern.Dispatcher
  require Pattern

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
    Dispatcher.register(pid, Pattern.new(fn %Event{body: %TestEventA{}} -> true end), 1)
    Dispatcher.register(pid, Pattern.new(fn %Event{body: %TestEventB{}} -> true end), 2)
    assert [1] == Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert [2] == Dispatcher.dispatch(pid, %Event{body: %TestEventB{}})
    assert [] == Dispatcher.dispatch(pid, %Event{body: %TestEventC{}})
  end

  test "returns multiple matched dispatch", %{pid: pid} do
    Dispatcher.register(pid, Pattern.new(fn %Event{body: %TestEventA{}} -> true end), 1)
    Dispatcher.register(pid, Pattern.new(fn %Event{body: %TestEventA{}} -> true end), 2)
    Dispatcher.register(pid, Pattern.new(fn %Event{body: %TestEventB{}} -> true end), 3)
    dispatch = Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert MapSet.new([1, 2]) == MapSet.new(dispatch)
  end

  test "deletes subscription", %{pid: pid} do
    pattern_1 = Pattern.new(fn %Event{body: %TestEventA{}} -> true end)
    pattern_2 = Pattern.new(fn %Event{body: %TestEventA{}} -> true end)
    pattern_3 = Pattern.new(fn %Event{body: %TestEventB{}} -> true end)
    Dispatcher.register(pid, pattern_1, 1)
    Dispatcher.register(pid, pattern_2, 2)
    Dispatcher.register(pid, pattern_3, 3)
    Dispatcher.unregister(pid, pattern_2, 2)
    Dispatcher.unregister(pid, pattern_3, 3)
    assert [1] == Dispatcher.dispatch(pid, %Event{body: %TestEventA{}})
    assert [] == Dispatcher.dispatch(pid, %Event{body: %TestEventB{}})
  end
end
