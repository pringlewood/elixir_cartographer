defmodule ElixirCartographer.Analyzers.ProcessArchitecture do
  @moduledoc """
  Maps supervision trees, GenServers, Agents, Tasks, and Broadway pipelines.
  """

  import ElixirCartographer.AstUtils, only: [parts_to_string: 1]

  defstruct genservers: [], supervisors: [], agents: [], tasks: [], broadway: []

  @doc """
  Analyze parsed files for OTP process patterns.
  """
  def analyze(parsed_files) do
    results =
      parsed_files
      |> Enum.flat_map(fn {path, %{ast: ast, content: content}} ->
        if ast do
          extract_processes(ast, path, content)
        else
          []
        end
      end)

    %__MODULE__{
      genservers: Enum.filter(results, &(&1.type == :genserver)),
      supervisors: Enum.filter(results, &(&1.type == :supervisor)),
      agents: Enum.filter(results, &(&1.type == :agent)),
      tasks: Enum.filter(results, &(&1.type == :task)),
      broadway: Enum.filter(results, &(&1.type == :broadway))
    }
  end

  defp extract_processes(ast, path, content) do
    {_, processes} = Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts} | rest]} = node, acc ->
        module_name = parts_to_string(parts)
        uses = extract_uses(rest)

        process =
          cond do
            "GenServer" in uses ->
              callbacks = extract_genserver_callbacks(rest)
              state_shape = detect_state_shape(rest)
              %{type: :genserver, module: module_name, path: path, callbacks: callbacks, state_shape: state_shape}

            "Supervisor" in uses || "DynamicSupervisor" in uses ->
              children = extract_supervisor_children(rest, content)
              strategy = extract_supervisor_strategy(rest)
              type = if "DynamicSupervisor" in uses, do: :dynamic_supervisor, else: :supervisor
              %{type: :supervisor, module: module_name, path: path, children: children, strategy: strategy, supervisor_type: type}

            "Agent" in uses ->
              %{type: :agent, module: module_name, path: path}

            "Task" in uses ->
              %{type: :task, module: module_name, path: path}

            "Broadway" in uses ->
              producers = extract_broadway_config(content)
              %{type: :broadway, module: module_name, path: path, producers: producers}

            true ->
              nil
          end

        if process do
          {node, [process | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(processes)
  end

  defp extract_uses(ast) do
    {_, uses} = Macro.prewalk(ast, [], fn
      {:use, _meta, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [parts_to_string(parts) | acc]}

      node, acc ->
        {node, acc}
    end)

    uses
  end

  defp extract_genserver_callbacks(ast) do
    {_, callbacks} = Macro.prewalk(ast, [], fn
      {:def, _, [{:handle_call, _, _args} | _]} = node, acc ->
        {node, [:handle_call | acc]}

      {:def, _, [{:handle_cast, _, _args} | _]} = node, acc ->
        {node, [:handle_cast | acc]}

      {:def, _, [{:handle_info, _, _args} | _]} = node, acc ->
        {node, [:handle_info | acc]}

      {:def, _, [{:handle_continue, _, _args} | _]} = node, acc ->
        {node, [:handle_continue | acc]}

      {:def, _, [{:init, _, _args} | _]} = node, acc ->
        {node, [:init | acc]}

      {:def, _, [{:terminate, _, _args} | _]} = node, acc ->
        {node, [:terminate | acc]}

      node, acc ->
        {node, acc}
    end)

    callbacks |> Enum.reverse() |> Enum.uniq()
  end

  defp detect_state_shape(ast) do
    {_, shapes} = Macro.prewalk(ast, [], fn
      # Pattern: %__MODULE__{...} in init
      {:%, _, [{:__MODULE__, _, _}, {:%{}, _, fields}]} = node, acc ->
        keys = Enum.map(fields, fn {k, _v} -> k end) |> Enum.filter(&is_atom/1)
        {node, [{:struct, keys} | acc]}

      # Pattern: %{key: val} in init
      {:def, _, [{:init, _, _} | body]} = node, acc ->
        map_keys = extract_map_keys(body)
        if map_keys != [] do
          {node, [{:map, map_keys} | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)

    case shapes do
      [{type, keys} | _] -> %{type: type, keys: keys}
      _ -> nil
    end
  end

  defp extract_map_keys(ast) do
    {_, keys} = Macro.prewalk(ast, [], fn
      {:%{}, _, fields} = node, acc when is_list(fields) ->
        new_keys =
          fields
          |> Enum.map(fn
            {k, _v} when is_atom(k) -> k
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        {node, new_keys ++ acc}

      node, acc ->
        {node, acc}
    end)

    keys |> Enum.uniq()
  end

  defp extract_supervisor_children(_ast, content) do
    # Parse children from content using regex (more reliable for this pattern)
    Regex.scan(~r/\{([A-Z][\w.]+)/, content)
    |> Enum.map(fn [_, module] -> module end)
    |> Enum.uniq()
  end

  defp extract_supervisor_strategy(ast) do
    {_, strategy} = Macro.prewalk(ast, nil, fn
      {:one_for_one, _, _} = node, _acc -> {node, :one_for_one}
      {:one_for_all, _, _} = node, _acc -> {node, :one_for_all}
      {:rest_for_one, _, _} = node, _acc -> {node, :rest_for_one}
      node, acc -> {node, acc}
    end)

    strategy
  end

  defp extract_broadway_config(content) do
    # Extract Broadway producer configuration
    case Regex.run(~r/producer:\s*\[[\s\S]*?module:\s*\{([^}]+)\}/, content) do
      [_, module_config] -> [String.trim(module_config)]
      _ -> []
    end
  end
end
