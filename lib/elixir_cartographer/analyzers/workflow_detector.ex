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

    # Build a map of schema module -> source content for extracting enum values
    schema_sources =
      parsed_files
      |> Enum.filter(fn {path, _} -> String.contains?(path, "/lib/") end)
      |> Map.new()

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
      # Try to find schema source for enum extraction
      schema_content = find_schema_source(schema.module, schema_sources)

      # Extract enum values from schema definition
      enum_values = extract_enum_values_from_schema(schema_content, schema.status_fields)

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
        (enum_values ++
           Enum.flat_map(related_transitions, & &1.values) ++
           Enum.flat_map(related_branches, & &1.values))
        |> Enum.uniq()
        |> filter_likely_status_values()

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

  # Find the source content for a schema module
  defp find_schema_source(module_name, schema_sources) do
    # Convert module name to likely file path patterns
    short_name =
      module_name
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    schema_sources
    |> Enum.find_value("", fn {path, %{content: content}} ->
      if String.contains?(path, short_name <> ".ex") do
        content
      end
    end)
  end

  # Extract enum values from Ecto.Enum definitions in schema source
  defp extract_enum_values_from_schema(content, status_fields) when is_binary(content) do
    status_field_names = Enum.map(status_fields, & &1.name) |> Enum.map(&to_string/1)

    # Pattern 1: Ecto.Enum with values: [...] or values: ~w(...)a
    enum_pattern = ~r/field\s+:(#{Enum.join(status_field_names, "|")})\s*,\s*Ecto\.Enum\s*,\s*values:\s*(\[[^\]]+\]|~w\([^)]+\)a?)/

    enum_values =
      Regex.scan(enum_pattern, content)
      |> Enum.flat_map(fn
        [_, _field, values_str] -> parse_values_list(values_str)
      end)

    # Pattern 2: validate_inclusion for status fields (with module attr or inline list)
    # Handles both `validate_inclusion(changeset, :status, [...])` and `|> validate_inclusion(:status, [...])`
    validation_pattern = ~r/validate_inclusion\(\s*(?:\w+\s*,\s*)?:(#{Enum.join(status_field_names, "|")})\s*,\s*(\[[^\]]+\]|~w\([^)]+\)a?|@\w+)/

    validation_values =
      Regex.scan(validation_pattern, content)
      |> Enum.flat_map(fn
        [_, _field, "@" <> attr_name] ->
          # Referenced module attribute - try to find it
          attr_pattern = ~r/@#{attr_name}\s+(\[[^\]]+\]|~w\([^)]+\)a?)/
          case Regex.run(attr_pattern, content) do
            [_, values_str] -> parse_values_list(values_str)
            _ -> []
          end
        [_, _field, values_str] ->
          parse_values_list(values_str)
      end)

    # Pattern 3: @statuses or @states module attribute
    attr_pattern = ~r/@(statuses?|states?|status_values?|state_values?)\s+(\[[^\]]+\]|~w\([^)]+\)a?)/

    attr_values =
      Regex.scan(attr_pattern, content)
      |> Enum.flat_map(fn
        [_, _attr, values_str] -> parse_values_list(values_str)
      end)

    (enum_values ++ validation_values ++ attr_values) |> Enum.uniq()
  end

  defp extract_enum_values_from_schema(_, _), do: []

  # Parse a list of values from various Elixir syntax forms
  defp parse_values_list(str) do
    cond do
      # ~w(foo bar baz)a format
      String.starts_with?(str, "~w") ->
        str
        |> String.replace(~r/~w\(|\)a?/, "")
        |> String.split(~r/\s+/, trim: true)

      # [:foo, :bar, :baz] or ["foo", "bar"] format
      String.starts_with?(str, "[") ->
        str
        |> String.replace(~r/[\[\]]/, "")
        |> String.split(",")
        |> Enum.map(fn s ->
          s
          |> String.trim()
          |> String.replace(~r/^:|^"|"$/, "")
        end)
        |> Enum.reject(&(&1 == ""))

      true ->
        []
    end
  end

  # Filter to only likely status/state values
  defp filter_likely_status_values(values) do
    known_good = ~w(
      pending active inactive completed done finished
      triggered acknowledged resolved
      draft submitted approved rejected
      open closed cancelled canceled
      processing queued scheduled
      failed error success
      enabled disabled
      started stopped paused running
      published unpublished archived
      accepted declined
      sent delivered read
      new in_progress on_hold blocked
      investigating identified monitoring
      critical high medium low info
    )

    values
    |> Enum.filter(fn v ->
      v_lower = String.downcase(v)
      # Keep if it's a known status value OR looks like a status
      v_lower in known_good ||
        String.contains?(v_lower, "status") ||
        String.contains?(v_lower, "state") ||
        String.ends_with?(v_lower, "ed") ||
        String.ends_with?(v_lower, "ing")
    end)
  end
end
