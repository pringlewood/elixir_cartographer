defmodule ElixirCartographer.Pipeline do
  @moduledoc """
  Orchestrates the full analysis pipeline across all 4 layers.
  """

  alias ElixirCartographer.{Config, Progress}
  alias ElixirCartographer.Analyzers.{
    ModuleGraph,
    EctoSchemas,
    ProcessArchitecture,
    RouteMapper,
    LiveViewAnalyzer,
    ConfigMatrix,
    ErrorTaxonomy,
    WorkflowDetector
  }
  alias ElixirCartographer.Miners.{GitMiner, TestMiner}
  alias ElixirCartographer.Synthesis.{AgentsMdGenerator, CompactGenerator, ContextDocsGenerator}

  @doc """
  Run the full pipeline and return results.
  """
  def run(%Config{} = config) do
    Progress.section("Elixir Cartographer v0.1.0")
    Progress.info("Analyzing: #{config.project_path}")
    Progress.info("Output:    #{config.output_path}")

    pipeline_start = System.monotonic_time(:millisecond)

    # Layer 1: Static Analysis
    Progress.section("Layer 1: Static Analysis")
    source_files = discover_files(config)
    parsed_files = parse_files(source_files)

    t = Progress.start("Module graph analysis")
    module_graph = ModuleGraph.analyze(parsed_files)
    Progress.info("Found #{map_size(module_graph.modules)} modules")
    Progress.done(t)

    t = Progress.start("Ecto schema extraction")
    schemas = EctoSchemas.analyze(parsed_files)
    Progress.info("Found #{length(schemas)} schemas")
    Progress.done(t)

    t = Progress.start("Process architecture mapping")
    processes = ProcessArchitecture.analyze(parsed_files)
    Progress.info("Found #{length(processes.genservers)} GenServers, #{length(processes.supervisors)} supervisors")
    Progress.done(t)

    t = Progress.start("Route & plug mapping")
    routes = RouteMapper.analyze(parsed_files, config)
    Progress.info("Found #{length(routes.routes)} routes, #{length(routes.pipelines)} pipelines")
    Progress.done(t)

    t = Progress.start("LiveView & component analysis")
    live_view = LiveViewAnalyzer.analyze(parsed_files)
    Progress.info("Found #{length(live_view.live_views)} LiveViews, #{length(live_view.live_components)} components, #{length(live_view.function_components)} function components")
    Progress.done(t)

    t = Progress.start("Configuration matrix")
    config_matrix = ConfigMatrix.analyze(config)
    Progress.info("Found #{length(config_matrix.env_vars)} env vars, #{length(config_matrix.app_configs)} app configs")
    Progress.done(t)

    t = Progress.start("Error taxonomy")
    errors = ErrorTaxonomy.analyze(parsed_files)
    Progress.info("Found #{length(errors)} error patterns")
    Progress.done(t)

    t = Progress.start("Workflow & state machine detection")
    workflows = WorkflowDetector.analyze(parsed_files, schemas)
    Progress.info("Found #{length(workflows)} workflow patterns")
    Progress.done(t)

    # Layer 2: Git Mining
    git_data =
      if config.skip_git do
        Progress.section("Layer 2: Git Mining (skipped)")
        GitMiner.empty()
      else
        Progress.section("Layer 2: Git Mining")
        t = Progress.start("Mining git history")
        data = GitMiner.analyze(config)
        Progress.info("Analyzed #{data.total_commits} commits, found #{length(data.hotspots)} hotspots")
        Progress.done(t)
        data
      end

    # Layer 3: Test Mining
    test_data =
      if config.skip_tests do
        Progress.section("Layer 3: Test Mining (skipped)")
        TestMiner.empty()
      else
        Progress.section("Layer 3: Test Mining")
        t = Progress.start("Mining test files")
        data = TestMiner.analyze(config)
        Progress.info("Found #{data.total_tests} tests in #{length(data.test_files)} files")
        Progress.done(t)
        data
      end

    # Layer 4: Synthesis
    Progress.section("Layer 4: Synthesis")

    analysis = %{
      config: config,
      module_graph: module_graph,
      schemas: schemas,
      processes: processes,
      routes: routes,
      live_view: live_view,
      config_matrix: config_matrix,
      errors: errors,
      workflows: workflows,
      git: git_data,
      tests: test_data,
      source_files: source_files,
      parsed_files: parsed_files
    }

    t = Progress.start("Generating AGENTS.md#{if config.compact, do: " (compact)", else: ""}")
    agents_md =
      if config.compact do
        CompactGenerator.generate(analysis)
      else
        AgentsMdGenerator.generate(analysis)
      end
    Progress.done(t)

    t = Progress.start("Generating context docs")
    context_docs = ContextDocsGenerator.generate(analysis)
    Progress.done(t)

    t = Progress.start("Writing output files")
    write_output(config, agents_md, context_docs)
    Progress.done(t)

    elapsed = System.monotonic_time(:millisecond) - pipeline_start
    Progress.section("Complete")
    Progress.info("Total time: #{Float.round(elapsed / 1000, 1)}s")
    Progress.info("Output written to: #{config.output_path}")

    {:ok, analysis}
  end

  defp discover_files(%Config{lib_path: lib_path}) do
    t = Progress.start("Discovering source files")

    files =
      if File.dir?(lib_path) do
        Path.wildcard(Path.join(lib_path, "**/*.ex"))
      else
        []
      end

    Progress.info("Found #{length(files)} .ex files")
    Progress.done(t)
    files
  end

  defp parse_files(files) do
    t = Progress.start("Parsing AST for all files")

    results =
      files
      |> Enum.map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            case Code.string_to_quoted(content, file: path, columns: true) do
              {:ok, ast} -> {path, %{ast: ast, content: content}}
              {:error, _} -> {path, %{ast: nil, content: content}}
            end

          {:error, _} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    parsed = Enum.count(results, fn {_, %{ast: ast}} -> ast != nil end)
    Progress.info("Successfully parsed #{parsed}/#{length(files)} files")
    Progress.done(t)
    results
  end

  defp write_output(config, agents_md, context_docs) do
    File.mkdir_p!(config.output_path)

    # Write AGENTS.md
    agents_path = Path.join(config.output_path, "AGENTS.md")
    File.write!(agents_path, agents_md)

    # Write context docs
    docs_dir = Path.join(config.output_path, "contexts")
    File.mkdir_p!(docs_dir)

    Enum.each(context_docs, fn {filename, content} ->
      File.write!(Path.join(docs_dir, filename), content)
    end)
  end
end
