defmodule ElixirCartographer.Analyzers.EctoSchemas do
  @moduledoc """
  Extracts Ecto schemas: fields, types, associations, and relationships.
  """

  @doc """
  Analyze parsed files for Ecto schemas.
  """
  def analyze(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{ast: ast, content: content}} ->
      if ast && is_schema_file?(content) do
        extract_schemas(ast, path)
      else
        []
      end
    end)
  end

  defp is_schema_file?(content) do
    String.contains?(content, "use Ecto.Schema") ||
      String.contains?(content, "schema ") ||
      String.contains?(content, "embedded_schema")
  end

  defp extract_schemas(ast, path) do
    {_, schemas} = Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts} | rest]} = node, acc ->
        module_name = Enum.map_join(parts, ".", &to_string/1)

        case extract_schema_info(rest) do
          nil -> {node, acc}
          schema_info ->
            schema = Map.merge(schema_info, %{
              module: module_name,
              path: path,
              changesets: extract_changesets(rest),
              validations: extract_validations(rest)
            })
            {node, [schema | acc]}
        end

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(schemas)
  end

  defp extract_schema_info(ast) do
    {_, info} = Macro.prewalk(ast, nil, fn
      {:schema, _, [table_name | body]} = node, _acc when is_binary(table_name) ->
        fields = extract_fields(body)
        assocs = extract_associations(body)
        {node, %{table: table_name, fields: fields, associations: assocs, type: :schema}}

      {:embedded_schema, _, body} = node, _acc ->
        fields = extract_fields(body)
        assocs = extract_associations(body)
        {node, %{table: nil, fields: fields, associations: assocs, type: :embedded}}

      node, acc ->
        {node, acc}
    end)

    info
  end

  defp extract_fields(ast) do
    {_, fields} = Macro.prewalk(ast, [], fn
      {:field, _, [name, type | opts]} = node, acc when is_atom(name) ->
        field = %{
          name: name,
          type: format_type(type),
          opts: extract_field_opts(opts)
        }
        {node, [field | acc]}

      {:field, _, [name, type]} = node, acc when is_atom(name) ->
        {node, [%{name: name, type: format_type(type), opts: %{}} | acc]}

      {:field, _, [name]} = node, acc when is_atom(name) ->
        {node, [%{name: name, type: ":string", opts: %{}} | acc]}

      {:timestamps, _, _} = node, acc ->
        {node, [
          %{name: :inserted_at, type: ":naive_datetime", opts: %{}},
          %{name: :updated_at, type: ":naive_datetime", opts: %{}}
          | acc
        ]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(fields)
  end

  defp extract_associations(ast) do
    {_, assocs} = Macro.prewalk(ast, [], fn
      {:has_many, _, [name, target | _opts]} = node, acc ->
        {node, [%{type: :has_many, name: name, target: format_target(target)} | acc]}

      {:has_one, _, [name, target | _opts]} = node, acc ->
        {node, [%{type: :has_one, name: name, target: format_target(target)} | acc]}

      {:belongs_to, _, [name, target | _opts]} = node, acc ->
        {node, [%{type: :belongs_to, name: name, target: format_target(target)} | acc]}

      {:many_to_many, _, [name, target | _opts]} = node, acc ->
        {node, [%{type: :many_to_many, name: name, target: format_target(target)} | acc]}

      {:embeds_one, _, [name | _rest]} = node, acc ->
        {node, [%{type: :embeds_one, name: name, target: to_string(name)} | acc]}

      {:embeds_many, _, [name | _rest]} = node, acc ->
        {node, [%{type: :embeds_many, name: name, target: to_string(name)} | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(assocs)
  end

  defp extract_changesets(ast) do
    {_, changesets} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _args} | _body]} = node, acc
      when is_atom(name) and name in [:changeset, :create_changeset, :update_changeset, :registration_changeset] ->
        {node, [name | acc]}

      {:def, _, [{name, _, _args} | _body]} = node, acc when is_atom(name) ->
        name_str = to_string(name)
        if String.contains?(name_str, "changeset") do
          {node, [name | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(changesets) |> Enum.uniq()
  end

  defp extract_validations(ast) do
    {_, validations} = Macro.prewalk(ast, [], fn
      {:validate_required, _, [fields | _]} = node, acc ->
        {node, [{:required, format_validation_fields(fields)} | acc]}

      {:validate_format, _, [field | _]} = node, acc when is_atom(field) ->
        {node, [{:format, field} | acc]}

      {:validate_length, _, [field | _]} = node, acc when is_atom(field) ->
        {node, [{:length, field} | acc]}

      {:validate_inclusion, _, [field | _]} = node, acc when is_atom(field) ->
        {node, [{:inclusion, field} | acc]}

      {:unique_constraint, _, [field | _]} = node, acc when is_atom(field) ->
        {node, [{:unique, field} | acc]}

      {:foreign_key_constraint, _, [field | _]} = node, acc when is_atom(field) ->
        {node, [{:foreign_key, field} | acc]}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(validations)
  end

  defp format_type({:__aliases__, _, parts}), do: Enum.map_join(parts, ".", &to_string/1)
  defp format_type(atom) when is_atom(atom), do: inspect(atom)
  defp format_type({:parameterized, _, _}), do: ":parameterized"
  defp format_type({:array, _, [inner]}), do: "{:array, #{format_type(inner)}}"
  defp format_type({:map, _, _}), do: ":map"
  defp format_type(other), do: inspect(other)

  defp format_target({:__aliases__, _, parts}), do: Enum.map_join(parts, ".", &to_string/1)
  defp format_target(atom) when is_atom(atom), do: to_string(atom)
  defp format_target(other), do: inspect(other)

  defp format_validation_fields(fields) when is_list(fields), do: fields
  defp format_validation_fields(field) when is_atom(field), do: [field]
  defp format_validation_fields(_), do: []

  defp extract_field_opts([opts]) when is_list(opts), do: Map.new(opts)
  defp extract_field_opts(_), do: %{}
end
