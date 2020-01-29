defmodule Cizen.Filter.Code do
  @moduledoc false
  alias Cizen.Filter

  @type t :: {:access, keys} | {:call, [{module, fun} | [term]]} | {atom, [term]} | term
  @type ast :: any
  @type key :: term
  @type keys :: [key]
  @type vars :: %{atom => keys}

  @doc false
  @spec translate(ast, vars, Macro.Env.t()) :: t
  def translate(expression, vars, env) do
    Macro.postwalk(expression, &walk(&1, vars, env))
  end

  defmacro as_code(vars \\ [], do: block) do
    translate(block, Enum.into(vars, %{}), __CALLER__)
  end

  @doc false
  @spec all([t]) :: t
  def all([]), do: true
  def all([code]), do: code
  def all([code | tail]), do: code_and(code, all(tail))

  @doc false
  @spec any([t]) :: t
  def any([]), do: false
  def any([code]), do: code
  def any([code | tail]), do: code_or(code, any(tail))

  @doc false
  @spec expand_embedded_filters(ast, Macro.Env.t()) :: t
  def expand_embedded_filters(expression, env) do
    Macro.prewalk(expression, fn node ->
      case node do
        {{:., _, [{:__aliases__, _, [:Filter]}, :new]}, _, _} ->
          {filter, _} =
            node
            |> Code.eval_quoted([], env)

          filter

        node ->
          node
      end
    end)
  end

  @doc false
  # Puts prefix recursively to expand embedded filters.
  def with_prefix({:access, keys}, prefix) do
    {:access, prefix ++ keys}
  end

  def with_prefix({op, args}, prefix) when is_atom(op) and is_list(args) do
    args = Enum.map(args, &with_prefix(&1, prefix))
    {op, args}
  end

  def with_prefix(node, _prefix), do: node

  @spec walk(ast, vars, Macro.Env.t()) :: ast
  # Additional operators
  # input: `is_nil(x)`
  @additional_operators [:is_nil, :to_string, :to_charlist, :is_map]
  defp walk({op, _, args} = node, _vars, _env) when op in @additional_operators do
    if Enum.any?(args, &access_code_exists?(&1)) do
      # literal tuple
      code_op(op, args)
    else
      # static expression
      node
    end
  end

  # Skip . operator (field access is handled in below)
  defp walk({:., _, _} = node, _vars, _env), do: node

  # input: `value.key`
  defp walk({{:., _, [{:access, keys}, key]}, _, []}, _vars, _env) do
    code_access(append_key(keys, key))
  end

  # input: `value[key]`
  defp walk({{:., _, [Access, :get]}, _, [{:access, keys}, key]}, _vars, _env) do
    code_access(append_key(keys, key))
  end

  # input: `MyModule.func(arg1, arg2)`
  defp walk({{:., _, [module, function]}, _, args} = node, _vars, env) do
    expanded_module = Macro.expand(module, env)

    cond do
      expanded_module == Filter and function == :match? ->
        # Embedded filter
        case args do
          [%Filter{code: code}, {:access, keys}] ->
            quote do
              unquote(__MODULE__).with_prefix(unquote(code), unquote(keys))
            end

          [filter, {:access, keys}] ->
            quote do
              unquote(__MODULE__).with_prefix(unquote(filter).code, unquote(keys))
            end
        end

      Enum.any?(args, &access_code_exists?(&1)) ->
        # Function call
        code_call(module, function, args)

      true ->
        # static expression
        node
    end
  end

  # input `var`
  defp walk({first, _, third} = node, vars, _env) when is_atom(first) and not is_list(third) do
    if Map.has_key?(vars, first) do
      keys = Map.get(vars, first)

      code_access(keys)
    else
      node
    end
  end

  defp walk({fun, _, args} = node, vars, env) when is_atom(fun) do
    cond do
      # input `value == 42`
      Macro.operator?(fun, length(args)) ->
        # Operator
        if Enum.any?(args, &access_code_exists?(&1)) do
          # literal tuple
          code_op(fun, args)
        else
          node
        end

      # input `imported_func(arg1, arg2)`
      args != [] ->
        # Function calls
        gen_call(node, vars, env)

      true ->
        node
    end
  end

  defp walk(node, _vars, _env), do: node

  # Finds {:access, keys} in the given ast.
  defp access_code_exists?(ast) do
    {_node, access_code_exists?} =
      Macro.prewalk(ast, false, fn node, access_code_exists? ->
        case node do
          {:access, _} ->
            {node, true}

          node ->
            {node, access_code_exists?}
        end
      end)

    access_code_exists?
  end

  defp gen_call({fun, _, args} = node, _vars, env) do
    if Enum.any?(args, &access_code_exists?(&1)) do
      arity = length(args)

      # find a function whitch matches the given name and arity.
      {module, _} =
        env.functions
        |> Enum.find({env.module, []}, fn {_module, functions} ->
          Enum.find(functions, fn
            {^fun, ^arity} ->
              true

            _ ->
              false
          end)
        end)

      # literal tuple
      code_call(module, fun, args)
    else
      node
    end
  end

  # Appends key
  @spec append_key(keys | ast, key) :: t
  defp append_key(keys, key) when is_list(keys), do: List.insert_at(keys, -1, key)

  # this case is required because as_code/2 translates ast with keys generated on runtime.
  defp append_key(keys, key) do
    quote bind_quoted: [keys: keys, key: key] do
      List.insert_at(keys, -1, key)
    end
  end

  @spec t === t :: t
  def left === right, do: {:==, [left, right]}
  @spec code_and(t, t) :: t
  def code_and(left, right), do: {:and, [left, right]}
  @spec code_or(t, t) :: t
  def code_or(left, right), do: {:or, [left, right]}
  @spec code_access(keys) :: t
  def code_access(keys), do: {:access, keys}
  @spec code_op(t, [t]) :: t
  def code_op(op, args), do: {op, args}
  @spec code_call(module, atom, [term]) :: t
  def code_call(module, function, args), do: {:call, [{module, function} | args]}
  @spec code_neg(t) :: t
  def code_neg(code), do: {:!, [code]}
end
