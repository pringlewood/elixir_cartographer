defmodule ElixirCartographer.Synthesis.CompactGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.{CompactGenerator, AgentsMdGenerator}
  alias ElixirCartographer.Analyzers.{ModuleGraph, EctoSchemas, ProcessArchitecture, RouteMapper, ConfigMatrix, ErrorTaxonomy, WorkflowDetector}
  alias ElixirCartographer.Miners.{GitMiner, TestMiner}

  @fixtures_path Path.expand("../../fixtures", __DIR__)

  setup do
    # Parse all fixtures
    fixture_files = Path.wildcard(Path.join(@fixtures_path, "*.ex"))

    parsed_files =
      Enum.reduce(fixture_files, %{}, fn path, acc ->
        content = File.read!(path)
        case Code.string_to_quoted(content, file: path) do
          {:ok, ast} -> Map.put(acc, path, %{ast: ast, content: content})
          _ -> acc
        end
      end)

    tmp = Path.join(System.tmp_dir!(), "cart_compact_#{:rand.uniform(999999)}")
    File.mkdir_p!(Path.join(tmp, "config"))
    File.mkdir_p!(Path.join(tmp, "lib"))

    config = %ElixirCartographer.Config{
      project_path: tmp,
      output_path: Path.join(tmp, "docs"),
      project_name: "test_app",
      lib_path: Path.join(tmp, "lib"),
      test_path: Path.join(tmp, "test"),
      config_path: Path.join(tmp, "config"),
      mix_exs_path: Path.join(tmp, "mix.exs"),
      compact: true
    }

    # Run analyzers
    module_graph = ModuleGraph.analyze(parsed_files)
    schemas = EctoSchemas.analyze(parsed_files)
    processes = ProcessArchitecture.analyze(parsed_files)
    routes = RouteMapper.analyze(parsed_files, config)
    config_matrix = ConfigMatrix.analyze(config)
    errors = ErrorTaxonomy.analyze(parsed_files)
    workflows = WorkflowDetector.analyze(parsed_files, schemas)

    analysis = %{
      config: config,
      module_graph: module_graph,
      schemas: schemas,
      processes: processes,
      routes: routes,
      config_matrix: config_matrix,
      errors: errors,
      workflows: workflows,
      git: GitMiner.empty(),
      tests: TestMiner.empty(),
      source_files: Map.keys(parsed_files),
      parsed_files: parsed_files,
      live_view: %ElixirCartographer.Analyzers.LiveViewAnalyzer{
        live_views: [],
        live_components: [],
        function_components: [],
        event_handlers: [],
        live_navigation: [],
        assigns_usage: [],
        streams_usage: [],
        pubsub_patterns: [],
        js_commands: [],
        uploads: [],
        hooks: []
      }
    }

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, analysis: analysis}
  end

  describe "generate/1" do
    test "produces non-empty markdown", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      assert is_binary(result)
      assert byte_size(result) > 50
    end

    test "includes project header with name", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      assert String.contains?(result, "# AGENTS.md — test_app")
    end

    test "includes stats in header", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      assert String.contains?(result, "Cartographer v0.1.0")
      assert String.contains?(result, "modules")
      assert String.contains?(result, "schemas")
    end

    test "is significantly shorter than full output", %{analysis: analysis} do
      compact = CompactGenerator.generate(analysis)
      full = AgentsMdGenerator.generate(analysis)
      assert byte_size(compact) < byte_size(full)
    end

    test "contains all contexts", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      contexts = analysis.module_graph.contexts

      Enum.each(contexts, fn {context_name, _} ->
        assert String.contains?(result, context_name),
               "Expected compact output to contain context: #{context_name}"
      end)
    end

    test "uses ## for section headers, not ###", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      # All section headers should use ## only
      lines = String.split(result, "\n")

      header_lines =
        lines
        |> Enum.filter(fn line ->
          String.starts_with?(String.trim(line), "#") and
          not String.starts_with?(String.trim(line), "# AGENTS")
        end)

      Enum.each(header_lines, fn line ->
        trimmed = String.trim(line)
        assert String.starts_with?(trimmed, "## "),
               "Expected '## ' header format, got: #{trimmed}"
      end)
    end

    test "does not contain config section", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      refute String.contains?(result, "## Configuration")
    end

    test "schemas use one-liner format", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)

      if analysis.schemas != [] do
        # Schemas in compact mode should be one-liners with field:type format
        schema = List.first(analysis.schemas)
        short = schema.module |> String.split(".") |> List.last()
        # Check it appears as a one-liner (no table format)
        refute String.contains?(result, "| Field | Type |"),
               "Compact mode should not use table format for schemas"
        assert String.contains?(result, short),
               "Expected compact output to reference schema #{short}"
      end
    end

    test "processes use one-liner format when present", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)

      if analysis.processes.genservers != [] do
        assert String.contains?(result, "GenServer:")
      end

      if analysis.processes.supervisors != [] do
        assert String.contains?(result, "Supervisor:")
      end
    end

    test "no horizontal rules", %{analysis: analysis} do
      result = CompactGenerator.generate(analysis)
      refute String.contains?(result, "---"),
             "Compact mode should not contain horizontal rules"
    end
  end
end
