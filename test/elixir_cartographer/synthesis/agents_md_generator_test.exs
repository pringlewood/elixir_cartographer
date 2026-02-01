defmodule ElixirCartographer.Synthesis.AgentsMdGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.AgentsMdGenerator
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

    tmp = Path.join(System.tmp_dir!(), "cart_synth_#{:rand.uniform(999999)}")
    File.mkdir_p!(Path.join(tmp, "config"))
    File.mkdir_p!(Path.join(tmp, "lib"))

    config = %ElixirCartographer.Config{
      project_path: tmp,
      output_path: Path.join(tmp, "docs"),
      project_name: "test_app",
      lib_path: Path.join(tmp, "lib"),
      test_path: Path.join(tmp, "test"),
      config_path: Path.join(tmp, "config"),
      mix_exs_path: Path.join(tmp, "mix.exs")
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
      parsed_files: parsed_files
    }

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, analysis: analysis}
  end

  describe "generate/1" do
    test "produces non-empty markdown", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert is_binary(result)
      assert byte_size(result) > 100
    end

    test "includes project header", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "AGENTS.md")
      assert String.contains?(result, "test_app")
    end

    test "includes project overview section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Project Overview")
    end

    test "includes domain contexts section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Domain Contexts")
    end

    test "includes data model section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Data Model")
    end

    test "includes process architecture section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Process Architecture")
    end

    test "includes API surface section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## API Surface")
    end

    test "includes workflow section", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Workflows & State Machines")
    end

    test "includes debugging guide", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "## Debugging Guide")
    end

    test "contains detected modules", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "SampleApp.Accounts.User")
    end

    test "contains schema information", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "users")
      assert String.contains?(result, "email")
    end

    test "contains route information", %{analysis: analysis} do
      result = AgentsMdGenerator.generate(analysis)
      assert String.contains?(result, "GET") || String.contains?(result, "PageController") || String.contains?(result, "LiveView")
    end
  end
end
