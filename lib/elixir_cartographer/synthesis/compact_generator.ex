defmodule ElixirCartographer.Synthesis.CompactGenerator do
  @moduledoc """
  Generates a condensed AGENTS.md optimized for token efficiency.

  Targets ~500-800 lines instead of 3,000+ by using one-liner formats
  for modules, schemas, routes, processes, and workflows.
  """

  alias ElixirCartographer.Synthesis.MermaidGenerator

  @doc """
  Generate the compact AGENTS.md content.
  """
  def generate(analysis) do
    [
      header(analysis),
      context_sections(analysis),
      schema_erd(analysis),
      context_graph(analysis),
      git_hotspots(analysis),
      test_summary(analysis)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp header(analysis) do
    config = analysis.config
    graph = analysis.module_graph
    module_count = map_size(graph.modules)
    schema_count = length(analysis.schemas)
    commit_count = analysis.git.total_commits

    stats =
      [
        "#{module_count} modules",
        "#{schema_count} schemas",
        if(commit_count > 0, do: "#{commit_count} commits", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")

    """
    # AGENTS.md — #{config.project_name}
    > Cartographer v0.1.0 | #{stats}
    """
  end

  defp context_sections(analysis) do
    contexts = analysis.module_graph.contexts
    modules = analysis.module_graph.modules
    schemas = analysis.schemas
    processes = analysis.processes
    workflows = analysis.workflows
    routes = analysis.routes
    lv = Map.get(analysis, :live_view)

    # Extract live routes for compact display
    live_routes =
      analysis.parsed_files
      |> Enum.filter(fn {path, _} -> String.contains?(path, "router.ex") end)
      |> Enum.flat_map(fn {_path, %{content: content}} ->
        ElixirCartographer.Analyzers.RouteMapper.extract_live_routes(content)
      end)

    contexts
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {context_name, module_names} ->
      ctx_lower = String.downcase(context_name)

      # Module one-liners
      module_lines =
        module_names
        |> Enum.map(fn name ->
          mod = Map.get(modules, name, %{public_functions: []})
          pub_fns = Map.get(mod, :public_functions, [])
          fn_list = pub_fns |> Enum.take(8) |> Enum.map_join(", ", fn f -> "#{f.name}/#{f.arity}" end)

          # Check if this is a schema
          schema = Enum.find(schemas, fn s -> s.module == name end)

          # Check if this is a GenServer/process
          genserver = Enum.find(processes.genservers, fn g -> g.module == name end)
          supervisor = Enum.find(processes.supervisors, fn s -> s.module == name end)

          # Check if this is a LiveView
          live_view = if lv, do: Enum.find(lv.live_views, fn v -> v.module == name end), else: nil

          # Check if this is a component
          func_comp = if lv, do: Enum.find(lv.function_components, fn fc -> fc.module == name end), else: nil
          live_comp = if lv, do: Enum.find(lv.live_components, fn c -> c.module == name end), else: nil

          cond do
            schema != nil ->
              format_schema_line(schema)

            genserver != nil ->
              format_genserver_line(genserver)

            supervisor != nil ->
              format_supervisor_line(supervisor)

            live_view != nil ->
              format_live_view_line(live_view)

            func_comp != nil ->
              format_function_component_line(func_comp)

            live_comp != nil ->
              format_live_component_line(live_comp)

            fn_list != "" ->
              "- #{short_name(name)} — #{fn_list}"

            true ->
              "- #{short_name(name)}"
          end
        end)

      # Workflow one-liners for this context
      workflow_lines =
        workflows
        |> Enum.filter(fn w -> String.contains?(w.module, ".#{context_name}.") end)
        |> Enum.map(fn w ->
          field = w.status_fields |> Enum.map(& &1.name) |> List.first() || "status"
          values = w.status_values |> Enum.take(8) |> Enum.join(" → ")
          "- Workflow: #{short_name(w.module)} [#{field}] — #{values}"
        end)

      # Route one-liners for this context
      route_lines =
        routes.routes
        |> Enum.filter(fn r ->
          String.downcase(r.controller) |> String.contains?(ctx_lower)
        end)
        |> Enum.map(fn r ->
          "- #{r.method} #{r.path} → #{short_name(r.controller)}.#{r.action}"
        end)

      # Live route one-liners for this context
      live_route_lines =
        live_routes
        |> Enum.filter(fn r ->
          String.downcase(r.module) |> String.contains?(ctx_lower)
        end)
        |> Enum.map(fn r ->
          "- LIVE #{r.path} → #{short_name(r.module)}"
        end)

      all_lines =
        (module_lines ++ workflow_lines ++ route_lines ++ live_route_lines)
        |> Enum.uniq()

      """
      ## #{context_name} (#{length(module_names)} modules)
      #{Enum.join(all_lines, "\n")}
      """
    end)
    |> Enum.join("\n")
  end

  defp schema_erd(analysis) do
    diagram = MermaidGenerator.schema_erd(analysis.schemas)

    if diagram == "" do
      ""
    else
      """
      ## Schema ERD
      #{diagram}
      """
    end
  end

  defp context_graph(analysis) do
    diagram = MermaidGenerator.context_graph(analysis.module_graph)

    if diagram == "" do
      ""
    else
      """
      ## Context Dependencies
      #{diagram}
      """
    end
  end

  defp git_hotspots(analysis) do
    git = analysis.git

    if git.total_commits == 0 || git.hotspots == [] do
      ""
    else
      hotspots =
        git.hotspots
        |> Enum.take(5)
        |> Enum.map_join("\n", fn h -> "- #{h.file} (#{h.fix_count} fixes)" end)

      """
      ## Git Hotspots
      #{hotspots}
      """
    end
  end

  defp test_summary(analysis) do
    tests = analysis.tests

    if tests.total_tests == 0 do
      ""
    else
      gaps =
        tests.coverage_gaps
        |> Enum.take(5)
        |> Enum.map_join("\n", fn g ->
          "- #{Path.relative_to(g.file, analysis.config.project_path)}"
        end)

      gap_section = if gaps != "", do: "\nTop coverage gaps:\n#{gaps}", else: ""

      """
      ## Tests
      #{tests.total_tests} tests across #{length(tests.test_files)} files#{gap_section}
      """
    end
  end

  # Format helpers

  defp format_schema_line(schema) do
    fields =
      schema.fields
      |> Enum.take(8)
      |> Enum.map_join(", ", fn f -> "#{f.name}:#{f.type}" end)

    assocs =
      if schema.associations != [] do
        schema.associations
        |> Enum.map_join(", ", fn a -> "#{a.type} → #{a.target}" end)
        |> then(&" | #{&1}")
      else
        ""
      end

    table_note = if schema.table, do: " (#{schema.table})", else: ""
    "- #{short_name(schema.module)}#{table_note} — #{fields}#{assocs}"
  end

  defp format_genserver_line(genserver) do
    callbacks = Enum.join(genserver.callbacks, ", ")
    "- GenServer: #{short_name(genserver.module)} (#{callbacks})"
  end

  defp format_supervisor_line(supervisor) do
    children = supervisor.children |> Enum.take(5) |> Enum.map_join(", ", &short_name/1)
    strategy = supervisor.strategy || "unknown"
    "- Supervisor: #{short_name(supervisor.module)} [#{strategy}] → #{children}"
  end

  defp format_live_view_line(live_view) do
    parts = []

    parts =
      if live_view.events != [] do
        parts ++ ["events: #{Enum.join(live_view.events, ", ")}"]
      else
        parts
      end

    parts =
      if Map.get(live_view, :streams, []) != [] do
        parts ++ ["streams: #{Enum.join(live_view.streams, ", ")}"]
      else
        parts
      end

    suffix = if parts != [], do: " — #{Enum.join(parts, " | ")}", else: ""
    "- LiveView: #{short_name(live_view.module)}#{suffix}"
  end

  defp format_function_component_line(fc) do
    attrs =
      if fc.attrs != [] do
        "attrs: #{Enum.map_join(fc.attrs, ", ", & &1.name)}"
      else
        nil
      end

    slots =
      if fc.slots != [] do
        "slots: #{Enum.join(fc.slots, ", ")}"
      else
        nil
      end

    parts = [attrs, slots] |> Enum.reject(&is_nil/1) |> Enum.join(" | ")
    suffix = if parts != "", do: " — #{parts}", else: ""
    "- Component: #{short_name(fc.module)}#{suffix}"
  end

  defp format_live_component_line(lc) do
    callbacks = Enum.join(lc.callbacks, ", ")
    events = if lc.events != [], do: " | events: #{Enum.join(lc.events, ", ")}", else: ""
    "- LiveComponent: #{short_name(lc.module)} (#{callbacks}#{events})"
  end

  defp short_name(module) do
    module
    |> to_string()
    |> String.split(".")
    |> List.last()
  end
end
