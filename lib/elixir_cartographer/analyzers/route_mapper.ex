defmodule ElixirCartographer.Analyzers.RouteMapper do
  @moduledoc """
  Maps Phoenix routes, plugs, and pipelines.
  """

  @doc """
  Analyze parsed files for Phoenix routing patterns.
  Returns routes, pipelines, scopes, and plugs.
  """
  def analyze(parsed_files, config) do
    # Find router file(s)
    router_files =
      parsed_files
      |> Enum.filter(fn {path, _} -> String.contains?(path, "router.ex") end)

    routes =
      router_files
      |> Enum.flat_map(fn {path, %{content: content}} ->
        extract_routes(content, path)
      end)

    pipelines =
      router_files
      |> Enum.flat_map(fn {_path, %{content: content}} ->
        extract_pipelines(content)
      end)

    scopes =
      router_files
      |> Enum.flat_map(fn {_path, %{content: content}} ->
        extract_scopes(content)
      end)

    plugs = extract_plugs(parsed_files, config)

    %{
      routes: routes,
      pipelines: pipelines,
      scopes: scopes,
      plugs: plugs
    }
  end

  defp extract_routes(content, _path) do
    http_methods = ~w(get post put patch delete head options)
    pattern = ~r/(#{Enum.join(http_methods, "|")})\s+"([^"]+)"\s*,\s*([A-Z][\w.]*)\s*,\s*:(\w+)/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_full, method, path_str, controller, action] ->
      %{
        method: String.upcase(method),
        path: path_str,
        controller: controller,
        action: action
      }
    end)
  end

  defp extract_pipelines(content) do
    # Match pipeline definitions
    pipeline_pattern = ~r/pipeline\s+:(\w+)\s+do([\s\S]*?)end/

    Regex.scan(pipeline_pattern, content)
    |> Enum.map(fn [_full, name, body] ->
      plugs = Regex.scan(~r/plug\s+:?([A-Za-z][\w.]*)/, body)
        |> Enum.map(fn [_, plug] -> plug end)

      %{name: name, plugs: plugs}
    end)
  end

  defp extract_scopes(content) do
    scope_pattern = ~r/scope\s+"([^"]+)"\s*(?:,\s*([A-Z][\w.]*))?\s*(?:,\s*as:\s*:(\w+))?\s*do/

    Regex.scan(scope_pattern, content)
    |> Enum.map(fn
      [_full, path] -> %{path: path, module: nil, as: nil}
      [_full, path, module] -> %{path: path, module: module, as: nil}
      [_full, path, module, as_name] -> %{path: path, module: module, as: as_name}
    end)
  end

  defp extract_plugs(parsed_files, _config) do
    parsed_files
    |> Enum.filter(fn {path, _} ->
      String.contains?(path, "/plugs/") || String.contains?(path, "_plug.ex")
    end)
    |> Enum.flat_map(fn {path, %{ast: ast}} ->
      if ast do
        extract_plug_modules(ast, path)
      else
        []
      end
    end)
  end

  defp extract_plug_modules(ast, path) do
    {_, plugs} = Macro.prewalk(ast, [], fn
      {:defmodule, _meta, [{:__aliases__, _, parts} | rest]} = node, acc ->
        module_name = Enum.map_join(parts, ".", &to_string/1)
        has_call = has_function?(rest, :call)
        has_init = has_function?(rest, :init)

        if has_call || has_init do
          {node, [%{module: module_name, path: path, has_call: has_call, has_init: has_init} | acc]}
        else
          {node, acc}
        end

      node, acc ->
        {node, acc}
    end)

    Enum.reverse(plugs)
  end

  defp has_function?(ast, name) do
    {_, found} = Macro.prewalk(ast, false, fn
      {:def, _, [{^name, _, _} | _]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)

    found
  end

  @doc """
  Extract live routes from router content.
  """
  def extract_live_routes(content) do
    live_pattern = ~r/live\s+"([^"]+)"\s*,\s*([A-Z][\w.]*)\s*(?:,\s*:(\w+))?/

    Regex.scan(live_pattern, content)
    |> Enum.map(fn
      [_full, path, module] -> %{path: path, module: module, action: nil, type: :live}
      [_full, path, module, action] -> %{path: path, module: module, action: action, type: :live}
    end)
  end
end
