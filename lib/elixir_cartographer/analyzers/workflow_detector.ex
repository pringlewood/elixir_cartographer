defmodule ElixirCartographer.Analyzers.WorkflowDetector do
  @moduledoc """
  Detects workflow and state machine patterns: status fields, transition functions,
  and state-dependent logic.
  """

  @status_field_names ~w(status state stage phase step workflow_state)a

  @doc """
  Analyze schemas and parsed files for workflow patterns.
  """
  def analyze(parsed_files, schemas) do
    # Find schemas with status-like fields
    status_schemas = find_status_schemas(schemas)

    # Find transition functions
    transitions =
      parsed_files
      |> Enum.flat_map(fn {path, %{ast: ast, content: content}} ->
        if ast do
          find_transitions(content, path)
        else
          []
        end
      end)

    # Find case/cond branches on status fields
    state_branches =
      parsed_files
      |> Enum.flat_map(fn {path, %{content: content}} ->
        find_state_branches(content, path)
      end)

    # Combine into workflow patterns
    status_schemas
    |> Enum.map(fn schema ->
      related_transitions =
        transitions
        |> Enum.filter(fn t ->
          String.contains?(t.context, schema_context(schema.module))
        end)

      related_branches =
        state_branches
        |> Enum.filter(fn b ->
          Enum.any?(schema.status_fields, fn f ->
            String.contains?(b.content, to_string(f.name))
          end)
        end)

      status_values =
        (Enum.flat_map(related_transitions, & &1.values) ++
           Enum.flat_map(related_branches, & &1.values))
        |> Enum.uniq()

      %{
        module: schema.module,
        status_fields: schema.status_fields,
        status_values: status_values,
        transitions: related_transitions,
        branches: length(related_branches),
        table: schema.table
      }
    end)
  end

  defp find_status_schemas(schemas) do
    schemas
    |> Enum.filter(fn schema ->
      Enum.any?(schema.fields, fn field ->
        field.name in @status_field_names ||
          String.contains?(to_string(field.name), "status") ||
          String.contains?(to_string(field.name), "state")
      end)
    end)
    |> Enum.map(fn schema ->
      status_fields =
        schema.fields
        |> Enum.filter(fn field ->
          field.name in @status_field_names ||
            String.contains?(to_string(field.name), "status") ||
            String.contains?(to_string(field.name), "state")
        end)

      %{module: schema.module, table: schema.table, status_fields: status_fields}
    end)
  end

  defp find_transitions(content, path) do
    # Pattern: function names suggesting state transitions
    transition_patterns = [
      ~r/def\s+(transition|change_status|update_status|move_to|transition_to|set_status|activate|deactivate|archive|complete|cancel|approve|reject|suspend|resume)\w*\s*\(/,
      ~r/def\s+\w*(status|state)_to_\w+/
    ]

    transition_patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [full | _] ->
        # Extract status values mentioned nearby
        context_area = extract_surrounding_context(content, full, 500)
        values = extract_status_values(context_area)

        %{
          function: String.trim(full),
          path: path,
          context: path,
          values: values
        }
      end)
    end)
  end

  defp find_state_branches(content, _path) do
    # Find case expressions that branch on status/state values
    pattern = ~r/case\s+\w+\.\s*(status|state|stage|phase)\s+do([\s\S]{0,500}?)end/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_full, field, body] ->
      values = extract_status_values(body)
      %{field: field, values: values, content: body}
    end)
  end

  defp extract_status_values(text) do
    # Extract atom-like status values
    atom_pattern = ~r/:(\w+)/
    string_pattern = ~r/"(\w+)"/

    atoms = Regex.scan(atom_pattern, text) |> Enum.map(fn [_, v] -> v end)
    strings = Regex.scan(string_pattern, text) |> Enum.map(fn [_, v] -> v end)

    (atoms ++ strings)
    |> Enum.filter(fn v ->
      v not in ~w(ok error true false nil __MODULE__ __struct__ do end if else) &&
        String.length(v) > 1 &&
        String.length(v) < 30
    end)
    |> Enum.uniq()
  end

  defp extract_surrounding_context(content, needle, radius) do
    case :binary.match(content, needle) do
      {start, _len} ->
        from = max(0, start - radius)
        to = min(byte_size(content), start + byte_size(needle) + radius)
        binary_part(content, from, to - from)

      :nomatch ->
        ""
    end
  end

  defp schema_context(module_name) do
    module_name
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join(".")
  end
end
