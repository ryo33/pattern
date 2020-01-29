defmodule PatternTest do
  use ExUnit.Case

  alias Pattern
  require Pattern

  defmodule(A, do: defstruct([:key1, :key2]))
  defmodule(B, do: defstruct([:key1, :key2, :a]))
  defmodule(C, do: defstruct([:key1, :key2, :b]))

  test "throw exception on a wrong struct destructure" do
    assert_raise CompileError, fn ->
      quoted =
        quote do
          Pattern.new(fn %A{key1: a, key2: b, key3: c} ->
            a + b + c == 3
          end)
        end

      Code.eval_quoted(quoted, [], __ENV__)
    end
  end

  test "checks type" do
    pattern = Pattern.new(fn %A{key1: a} -> a == "a" end)
    assert Pattern.match?(pattern, %A{key1: "a"})
    refute Pattern.match?(pattern, %B{key1: "a"})
  end

  test "all/1" do
    pattern_3 = Pattern.new(fn %A{key1: a} -> rem(a, 3) == 0 end)
    pattern_5 = Pattern.new(fn %A{key1: a} -> rem(a, 5) == 0 end)
    pattern = Pattern.all([pattern_3, pattern_5])
    assert Pattern.match?(pattern, %A{key1: 15})
    refute Pattern.match?(pattern, %A{key1: 5})
    refute Pattern.match?(pattern, %A{key1: 3})
    refute Pattern.match?(pattern, %A{key1: 1})
  end

  test "all/1 with an empty list" do
    pattern = Pattern.all([])
    assert Pattern.match?(pattern, %A{})
    assert Pattern.match?(pattern, nil)
  end

  test "any/1" do
    pattern_3 = Pattern.new(fn %A{key1: a} -> rem(a, 3) == 0 end)
    pattern_5 = Pattern.new(fn %A{key1: a} -> rem(a, 5) == 0 end)
    pattern = Pattern.any([pattern_3, pattern_5])
    assert Pattern.match?(pattern, %A{key1: 15})
    assert Pattern.match?(pattern, %A{key1: 5})
    assert Pattern.match?(pattern, %A{key1: 3})
    refute Pattern.match?(pattern, %A{key1: 1})
  end

  test "any/1 with an empty list" do
    pattern = Pattern.any([])
    refute Pattern.match?(pattern, %A{})
    refute Pattern.match?(pattern, true)
  end

  test "eval value" do
    assert Pattern.eval("a", %A{}) == "a"
  end

  test "eval access" do
    pattern =
      Pattern.new(fn %C{b: %B{a: %A{key2: c}}} ->
        c
      end)

    assert Pattern.eval(pattern.code, %C{b: %B{a: %A{key2: "a"}}}) == "a"
  end

  test "eval access to nil value" do
    pattern =
      Pattern.new(fn %C{b: %B{a: %A{key2: c}}} ->
        c == "c"
      end)

    assert Pattern.eval(pattern.code, %C{b: %B{a: nil}}) == false
  end

  test "eval root access" do
    pattern =
      Pattern.new(fn a ->
        a
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a"}) == %A{key1: "a"}
  end

  test "eval call" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        Enum.count(a)
      end)

    assert Pattern.eval(pattern.code, %A{key1: [1, 2, 3]}) == 3
  end

  test "eval is_nil" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        is_nil(a)
      end)

    assert Pattern.eval(pattern.code, %A{key1: :a}) == false
    assert Pattern.eval(pattern.code, %A{key1: nil}) == true
  end

  test "eval to_string" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        to_string(a)
      end)

    assert Pattern.eval(pattern.code, %A{key1: :atom}) == "atom"
  end

  test "eval to_charlist" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        to_charlist(a)
      end)

    assert Pattern.eval(pattern.code, %A{key1: :atom}) == 'atom'
  end

  test "eval not" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        not a
      end)

    assert Pattern.eval(pattern.code, %A{key1: true}) == false
    assert Pattern.eval(pattern.code, %A{key1: false}) == true
  end

  test "eval !" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        !a
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a"}) == false
    assert Pattern.eval(pattern.code, %A{key1: nil}) == true
  end

  test "eval and" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a and b
      end)

    assert Pattern.eval(pattern.code, %A{key1: true, key2: true}) == true
    assert Pattern.eval(pattern.code, %A{key1: true, key2: false}) == false
    assert Pattern.eval(pattern.code, %A{key1: false, key2: true}) == false
    assert Pattern.eval(pattern.code, %A{key1: false, key2: false}) == false
  end

  test "eval &&" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a && b
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a", key2: "b"}) == "b"
    assert Pattern.eval(pattern.code, %A{key1: nil, key2: "b"}) == nil
  end

  test "eval or" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a or b
      end)

    assert Pattern.eval(pattern.code, %A{key1: true, key2: true}) == true
    assert Pattern.eval(pattern.code, %A{key1: true, key2: false}) == true
    assert Pattern.eval(pattern.code, %A{key1: false, key2: true}) == true
    assert Pattern.eval(pattern.code, %A{key1: false, key2: false}) == false
  end

  test "eval ||" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a || b
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a", key2: "b"}) == "a"
    assert Pattern.eval(pattern.code, %A{key1: nil, key2: "b"}) == "b"
  end

  test "eval in" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a in b
      end)

    assert Pattern.eval(pattern.code, %A{key1: 1, key2: [1, 2]}) == true
    assert Pattern.eval(pattern.code, %A{key1: 3, key2: [1, 2]}) == false
  end

  test "eval .." do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a..b
      end)

    assert Pattern.eval(pattern.code, %A{key1: 1, key2: 10}) == 1..10
  end

  test "eval <>" do
    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a <> b
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a", key2: "b"}) == "ab"
  end

  test "eval operators" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        a * 2 == 42
      end)

    assert Pattern.eval(pattern.code, %A{key1: 21}) == true
    assert Pattern.eval(pattern.code, %A{key1: 1}) == false

    pattern =
      Pattern.new(fn %A{key1: a} ->
        -a
      end)

    assert Pattern.eval(pattern.code, %A{key1: 3}) == -3

    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        a && b
      end)

    assert Pattern.eval(pattern.code, %A{key1: "a", key2: "b"}) == "b"
  end

  test "multiple cases" do
    pattern =
      Pattern.new(fn
        %A{key1: a} -> a == "value"
        %B{key1: b} -> b == "value"
      end)

    assert Pattern.eval(pattern.code, %A{key1: "value"}) == true
    assert Pattern.eval(pattern.code, %B{key1: "value"}) == true
    refute Pattern.eval(pattern.code, %C{key1: "value"}) == true
    refute Pattern.eval(pattern.code, %A{key1: "another value"}) == true
  end

  test "multiple cases with a negative case" do
    pattern =
      Pattern.new(fn
        %A{key1: 0} -> false
        %A{key1: value} -> rem(value, 2) == 0
      end)

    refute Pattern.eval(pattern.code, %A{key1: 0})
    assert Pattern.eval(pattern.code, %A{key1: 2})
    refute Pattern.eval(pattern.code, %A{key1: 1})
    assert Pattern.eval(pattern.code, %A{key1: 4})
  end

  test "guard" do
    pattern =
      Pattern.new(fn
        %A{key1: a, key2: b} when a in [:a, :b, :c] and not is_nil(b) -> false
        %A{key1: a} when a in [:a, :b, :c] -> true
      end)

    assert Pattern.eval(pattern.code, %A{key1: :a, key2: nil})
    refute Pattern.eval(pattern.code, %A{key1: :a, key2: :a})
    assert Pattern.eval(pattern.code, %A{key1: :a})
    refute Pattern.eval(pattern.code, %A{key1: :d})
  end
end
