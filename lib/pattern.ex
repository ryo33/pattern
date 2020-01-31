defmodule Pattern do
  @moduledoc """
  Creates a pattern.

  ## Basic

      Pattern.new(
        fn %Event{body: %SomeEvent{field: value}} ->
          value == :a
        end
      )

      Pattern.new(
        fn %Event{body: %SomeEvent{field: :a}} -> true end
      )

      value = :a
      Pattern.new(
        fn %Event{body: %SomeEvent{field: ^value}} -> true end
      )

  ## With guard

      Pattern.new(
        fn %Event{source_saga_id: source} when not is_nil(source) -> true end
      )

  ## Matches all

      Pattern.new(fn _ -> true end)

  ## Matches the specific type of struct

      Pattern.new(
        fn %Event{source_saga: %SomeSaga{}} -> true end
      )

  ## Compose patterns

      Pattern.new(
        fn %Event{body: %SomeEvent{field: value}} ->
          Pattern.match?(other_pattern, value)
        end
      )

  ## Multiple patterns

      Pattern.any([
        Pattern.new(fn %Event{body: %Resolve{id: id}} -> id == "some id" end),
        Pattern.new(fn %Event{body: %Reject{id: id}} -> id == "some id" end)
      ])

  ## Multiple cases

      Pattern.new(fn
        %Event{body: %SomeEvent{field: :ignore}} -> false
        %Event{body: %SomeEvent{field: value}} -> true
      end)
  """

  @type t :: %__MODULE__{}

  defstruct code: true

  alias Pattern.{Code, Compiler}

  @doc """
  Creates a pattern with the given anonymous function.
  """
  defmacro new(pattern) do
    # Evals the given pattern as a struct.
    struct =
      pattern
      |> Macro.prewalk(fn
        # Transforms `fn args1 -> expression1; args2 -> expression2; ... end`
        # into [args1, args2, ...]
        {:fn, _, cases} ->
          quote do: [unquote_splicing(cases)]

        {:->, _, [args, _expression]} ->
          args

        # Removes a guard clause
        {:when, _, [args, _guard]} ->
          args

        # Ignores a match with pin operator
        {:^, _, [{_var, _, _}]} ->
          {:_, [], nil}

        # Ignores a binding
        {_var, _, args} when not is_list(args) ->
          {:_, [], nil}

        node ->
          node
      end)

    quote(do: match?(unquote(struct), nil))
    |> Elixir.Code.eval_quoted([], __CALLER__)

    code = Compiler.compile(pattern, __CALLER__)

    quote do
      %unquote(__MODULE__){
        code: unquote(code)
      }
    end
  end

  @doc """
  Checks whether the given struct matches or not.
  """
  @spec match?(t, term) :: boolean
  def match?(%__MODULE__{code: code}, struct) do
    if eval(code, struct), do: true, else: false
  end

  @doc """
  Joins the given patterns with `and`.
  """
  @spec all([t()]) :: t()
  def all(patterns) do
    code = patterns |> Enum.map(& &1.code) |> Code.all()
    %__MODULE__{code: code}
  end

  @doc """
  Joins the given patterns with `or`.
  """
  @spec any([t()]) :: t()
  def any(patterns) do
    code = patterns |> Enum.map(& &1.code) |> Code.any()
    %__MODULE__{code: code}
  end

  def eval({:access, keys}, struct) do
    Enum.reduce(keys, struct, fn key, struct ->
      Map.get(struct, key)
    end)
  end

  def eval({:call, [{module, fun} | args]}, struct) do
    args = args |> Enum.map(&eval(&1, struct))
    apply(module, fun, args)
  end

  @macro_unary_operators [:is_nil, :to_string, :to_charlist, :not, :!]
  for operator <- @macro_unary_operators do
    def eval({unquote(operator), [arg]}, struct) do
      Kernel.unquote(operator)(eval(arg, struct))
    end
  end

  @macro_binary_operators [:and, :&&, :or, :||, :in, :.., :<>]
  for operator <- @macro_binary_operators do
    def eval({unquote(operator), [arg1, arg2]}, struct) do
      Kernel.unquote(operator)(eval(arg1, struct), eval(arg2, struct))
    end
  end

  def eval({operator, args}, struct) do
    args = args |> Enum.map(&eval(&1, struct))
    apply(Kernel, operator, args)
  end

  def eval(value, _struct) do
    value
  end
end
