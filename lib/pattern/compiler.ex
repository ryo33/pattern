defmodule Pattern.Compiler do
  @moduledoc false
  alias Pattern.Code
  import Code, only: [as_code: 2]

  # filter style
  # input: `fn %{a: a} -> a == :ok end`
  def compile(pattern_or_filter, env) do
    {:fn, _, fncases} = to_filter(pattern_or_filter)
    # Merges cases
    {codes, _guards} =
      fncases
      |> Enum.reduce({[], []}, fn fncase, {codes, guards_of_above_fncases} ->
        {code, guard} = read_fncase(fncase, env)

        code =
          guards_of_above_fncases
          |> Enum.reverse()
          # Makes guards of above fncases nagative
          |> Enum.map(fn guard -> Code.not_(guard) end)
          # guard for this case
          |> List.insert_at(-1, guard)
          |> Code.all()
          |> gen_and(code)

        {[code | codes], [guard | guards_of_above_fncases]}
      end)

    codes
    |> Enum.reverse()
    |> Code.any()
  end

  # input `fn case1; case2 end`
  def to_filter({:fn, _, _fncases} = filter), do: filter
  # input `%A{a: list} when is_list(list)`
  def to_filter({:when, _, _} = pattern), do: quote(do: fn unquote(pattern) -> true end)
  # input `%A{a: 3}`
  def to_filter({:%, _, _} = pattern), do: quote(do: fn unquote(pattern) -> true end)
  # input `%{a: 3}`
  def to_filter({:%{}, _, _} = pattern), do: quote(do: fn unquote(pattern) -> true end)

  # Reads fncase
  @spec read_fncase(Code.ast(), Macro.Env.t()) :: {Code.t(), [Code.t()]}
  defp read_fncase({:->, _, [[header], {:__block__, _, [expression]}]}, env) do
    # Ignores :__block__
    read_fncase({:->, [], [[header], expression]}, env)
  end

  defp read_fncase({:->, _, [[header], expression]}, env) do
    {vars, codes} = read_header(header, env)

    guard =
      codes
      |> Enum.reverse()
      |> Code.all()

    code =
      expression
      |> Code.expand_embedded_patterns(env)
      |> Code.translate(vars, env)

    {code, guard}
  end

  # Reads prefix and guard codes (reversed) from the given expression
  @spec read_header(Code.ast(), Macro.Env.t()) :: {Code.vars(), [Code.t()]}
  defp read_header(header, env), do: read_header(header, %{}, [], [], env)

  # * vars - accessible variables
  # * codes - codes generated from guard expressions
  # * prefix - prefix keys
  # * env - `Macro.Env`
  @spec read_header(Code.ast(), Code.vars(), [Code.t()], [term], Macro.Env.t()) ::
          {Code.vars(), [Code.t()]}
  # input: `%{key: atom} when atom in [:a, :b, :c]`
  defp read_header({:when, _, [header, guard]}, vars, codes, prefix, env) do
    # read the header
    {vars, codes} = read_header(header, vars, codes, prefix, env)
    # translate the guard case
    codes = [Code.translate(guard, vars, env) | codes]
    {vars, codes}
  end

  # input: `%MyStruct{key1: var, key2: 42}`
  defp read_header({:%, _, [module, {:%{}, _, pairs}]}, vars, codes, prefix, env) do
    code =
      as_code context_value: prefix do
        is_map(context_value) and context_value.__struct__ == module
      end

    handle_key_value_pairs(pairs, vars, [code | codes], prefix, env)
  end

  # input: `%{key1: var, key2: 42}`
  defp read_header({:%{}, _, pairs}, vars, codes, prefix, env) do
    code =
      as_code context_value: prefix do
        is_map(context_value)
      end

    handle_key_value_pairs(pairs, vars, [code | codes], prefix, env)
  end

  # input: `%MyStruct{a: 1} = var`
  defp read_header({:=, _, [struct, {var, meta, context}]}, vars, codes, prefix, env) do
    # read the struct
    {vars, codes} = read_header(struct, vars, codes, prefix, env)
    # read the var
    read_header({var, meta, context}, vars, codes, prefix, env)
  end

  # input: `^var`
  defp read_header({:^, _, [var]}, vars, codes, prefix, _env) do
    code =
      as_code context_value: prefix do
        context_value == var
      end

    {vars, [code | codes]}
  end

  # input: `var`
  defp read_header({var, _, _}, vars, codes, prefix, _env) do
    case Map.get(vars, var) do
      # bind the current value to the new variable.
      nil ->
        vars = Map.put(vars, var, prefix)
        {vars, codes}

      # variable exists.
      access ->
        code =
          as_code context_value: prefix, var: access do
            context_value == var
          end

        {vars, [code | codes]}
    end
  end

  # input: `42`
  defp read_header(value, vars, codes, prefix, _env) do
    code =
      as_code context_value: prefix do
        context_value == value
      end

    {vars, [code | codes]}
  end

  # Handles `[key1: var, key2: 42]` for a map or struct
  defp handle_key_value_pairs(pairs, vars, codes, prefix, env) do
    pairs
    |> Enum.reduce({vars, codes}, fn {key, value}, {vars, codes} ->
      read_header(value, vars, codes, List.insert_at(prefix, -1, key), env)
    end)
  end

  defp gen_and(true, arg2), do: arg2
  defp gen_and(arg1, true), do: arg1
  defp gen_and(arg1, arg2), do: Code.and_(arg1, arg2)
end
