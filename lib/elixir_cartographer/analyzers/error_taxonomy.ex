defmodule ElixirCartographer.Analyzers.ErrorTaxonomy do
  @moduledoc """
  Catalogs error handling patterns: rescue, catch, try blocks, error returns.
  """

  @doc """
  Analyze parsed files for error handling patterns.
  """
  def analyze(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{ast: ast, content: content}} ->
      if ast do
        rescue_patterns = extract_rescue_patterns(ast, path)
        error_returns = extract_error_returns(content, path)
        catch_patterns = extract_catch_patterns(content, path)
        rescue_patterns ++ error_returns ++ catch_patterns
      else
        []
      end
    end)
  end

  defp extract_rescue_patterns(ast, path) do
    {_, patterns} = Macro.prewalk(ast, [], fn
      {:rescue, rescue_clauses} = node, acc when is_list(rescue_clauses) ->
        new_patterns =
          rescue_clauses
          |> Enum.map(fn
            {:->, _, [[{:in, _, [_var, types]}], _body]} ->
              exception_types = extract_exception_types(types)
              %{type: :rescue, exceptions: exception_types, path: path}

            {:->, _, [[{:__aliases__, _, parts}], _body]} ->
              %{type: :rescue, exceptions: [Enum.map_join(parts, ".", &to_string/1)], path: path}

            _ ->
              %{type: :rescue, exceptions: ["_"], path: path}
          end)

        {node, new_patterns ++ acc}

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(patterns)
  end

  defp extract_exception_types(types) when is_list(types) do
    Enum.map(types, fn
      {:__aliases__, _, parts} -> Enum.map_join(parts, ".", &to_string/1)
      other -> inspect(other)
    end)
  end

  defp extract_exception_types({:__aliases__, _, parts}) do
    [Enum.map_join(parts, ".", &to_string/1)]
  end

  defp extract_exception_types(_), do: ["_"]

  defp extract_error_returns(content, path) do
    # {:error, reason} patterns
    pattern = ~r/\{:error,\s*:(\w+)\}/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_full, reason] ->
      %{type: :error_return, reason: reason, path: path}
    end)
    |> Enum.uniq_by(& &1.reason)
  end

  defp extract_catch_patterns(content, path) do
    if String.contains?(content, "catch") do
      catch_pattern = ~r/catch\s*\n\s*:(\w+)\s*,/

      Regex.scan(catch_pattern, content)
      |> Enum.map(fn [_full, kind] ->
        %{type: :catch, kind: kind, path: path}
      end)
    else
      []
    end
  end
end
