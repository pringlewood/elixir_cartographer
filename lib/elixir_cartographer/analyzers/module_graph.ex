defmodule ElixirCartographer.Analyzers.ModuleGraph do
  @moduledoc """
  Builds a graph of module relationships: who defines what, who uses/calls whom.
  """

  import ElixirCartographer.AstUtils, only: [parts_to_string: 1]

  defstruct modules: %{}, edges: [], contexts: %{}

  @doc """
  Analyze parsed files to build the module graph.
  """
  def analyze(parsed_files) do
    modules =
      parsed_files
      |> Enum.flat_map(fn {path, %{ast: ast}} ->
        if ast do
          extract_modules(ast, path)
        else
          []
        end
      end)
      |> Map.new(fn mod -> {mod.name, mod} end)

    edges = build_edges(modules)
    contexts = detect_contexts(modules)

    %__MODULE__{
      modules: modules,
      edges: edges,
      contexts: contexts
    }
  end

  defp extract_modules(ast, path) do
    {_, modules} = Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts} | rest]} = node, acc ->
        module_name = parts_to_string(parts)

        functions = extract_functions(rest)
        uses = extract_uses(rest)
        imports = extract_imports(rest)
        aliases = extract_aliases(rest)
        behaviours = extract_behaviours(rest)
        module_attrs = extract_module_attrs(rest)

        mod = %{
          name: module_name,
          path: path,
          functions: functions,
          uses: uses,
          imports: imports,
          aliases: aliases,
          behaviours: behaviours,
          module_attrs: module_attrs,
          public_functions: Enum.filter(functions, &(&1.visibility == :public)),
          private_functions: Enum.filter(functions, &(&1.visibility == :private))
        }

        {node, [mod | acc]}

      node, acc ->
        {node, acc}
    end)

    modules
  end

  defp extract_functions(ast) do
    {_, fns} = Macro.prewalk(ast, [], fn
      {:def, _meta, [{name, _, args} | _]} = node, acc when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {node, [%{name: name, arity: arity, visibility: :public} | acc]}

      {:defp, _meta, [{name, _, args} | _]} = node, acc when is_atom(name) ->
        arity = if is_list(args), do: length(args), else: 0
        {node, [%{name: name, arity: arity, visibility: :private} | acc]}

      node, acc ->
        {node, acc}
    end)

    fns |> Enum.reverse() |> Enum.uniq_by(&{&1.name, &1.arity})
  end

  defp extract_uses(ast) do
    {_, uses} = Macro.prewalk(ast, [], fn
      {:use, _meta, [{:__aliases__, _, parts} | _opts]} = node, acc ->
        {node, [parts_to_string(parts) | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(uses)
  end

  defp extract_imports(ast) do
    {_, imports} = Macro.prewalk(ast, [], fn
      {:import, _meta, [{:__aliases__, _, parts} | _opts]} = node, acc ->
        {node, [parts_to_string(parts) | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(imports)
  end

  defp extract_aliases(ast) do
    {_, aliases} = Macro.prewalk(ast, [], fn
      {:alias, _meta, [{:__aliases__, _, parts} | _opts]} = node, acc ->
        {node, [parts_to_string(parts) | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(aliases)
  end

  defp extract_behaviours(ast) do
    {_, behaviours} = Macro.prewalk(ast, [], fn
      {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]} = node, acc ->
        {node, [parts_to_string(parts) | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(behaviours)
  end

  defp extract_module_attrs(ast) do
    {_, attrs} = Macro.prewalk(ast, [], fn
      {:@, _, [{name, _, [value]}]} = node, acc when is_atom(name) and name not in [:doc, :moduledoc, :spec, :type, :typedoc, :impl, :behaviour, :callback, :derive, :enforce_keys] ->
        {node, [%{name: name, value: inspect(value, limit: 50)} | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(attrs)
  end

  defp build_edges(modules) do
    modules
    |> Enum.flat_map(fn {name, mod} ->
      alias_edges = Enum.map(mod.aliases, &%{from: name, to: &1, type: :alias})
      use_edges = Enum.map(mod.uses, &%{from: name, to: &1, type: :use})
      import_edges = Enum.map(mod.imports, &%{from: name, to: &1, type: :import})

      alias_edges ++ use_edges ++ import_edges
    end)
  end

  @doc """
  Detect Phoenix-style contexts by grouping modules by their namespace prefix.
  """
  def detect_contexts(modules) do
    modules
    |> Enum.group_by(fn {name, _mod} ->
      parts = String.split(name, ".")

      case parts do
        [_app, context | _rest] -> context
        _ -> "Root"
      end
    end)
    |> Enum.map(fn {context, mods} ->
      {context, Enum.map(mods, fn {name, _} -> name end)}
    end)
    |> Map.new()
  end
end
