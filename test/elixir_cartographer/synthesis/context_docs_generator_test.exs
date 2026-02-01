defmodule ElixirCartographer.Synthesis.ContextDocsGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.ContextDocsGenerator
  alias ElixirCartographer.Analyzers.{ModuleGraph, EctoSchemas}
  alias ElixirCartographer.Miners.{GitMiner, TestMiner}

  @fixtures_path Path.expand("../../fixtures", __DIR__)

  setup do
    fixture_files = Path.wildcard(Path.join(@fixtures_path, "*.ex"))

    parsed_files =
      Enum.reduce(fixture_files, %{}, fn path, acc ->
        content = File.read!(path)
        case Code.string_to_quoted(content, file: path) do
          {:ok, ast} -> Map.put(acc, path, %{ast: ast, content: content})
          _ -> acc
        end
      end)

    config = %ElixirCartographer.Config{
      project_path: "/tmp/test",
      output_path: "/tmp/test/docs",
      project_name: "test_app",
      lib_path: "/tmp/test/lib",
      test_path: "/tmp/test/test",
      config_path: "/tmp/test/config",
      mix_exs_path: "/tmp/test/mix.exs"
    }

    module_graph = ModuleGraph.analyze(parsed_files)
    schemas = EctoSchemas.analyze(parsed_files)

    analysis = %{
      config: config,
      module_graph: module_graph,
      schemas: schemas,
      processes: %ElixirCartographer.Analyzers.ProcessArchitecture{},
      routes: %{routes: [], pipelines: [], scopes: [], plugs: []},
      config_matrix: %{env_vars: [], app_configs: [], runtime_configs: [], config_files: []},
      errors: [],
      workflows: [],
      git: GitMiner.empty(),
      tests: TestMiner.empty(),
      source_files: Map.keys(parsed_files),
      parsed_files: parsed_files
    }

    {:ok, analysis: analysis}
  end

  describe "generate/1" do
    test "produces a list of {filename, content} tuples", %{analysis: analysis} do
      result = ContextDocsGenerator.generate(analysis)
      assert is_list(result)
      assert length(result) > 0

      Enum.each(result, fn {filename, content} ->
        assert is_binary(filename)
        assert String.ends_with?(filename, ".md")
        assert is_binary(content)
        assert byte_size(content) > 0
      end)
    end

    test "includes an index file", %{analysis: analysis} do
      result = ContextDocsGenerator.generate(analysis)
      filenames = Enum.map(result, &elem(&1, 0))
      assert "_index.md" in filenames
    end

    test "generates per-context files", %{analysis: analysis} do
      result = ContextDocsGenerator.generate(analysis)
      filenames = Enum.map(result, &elem(&1, 0))

      # Should have a file for the Accounts context
      assert Enum.any?(filenames, &String.contains?(&1, "accounts"))
    end

    test "index contains context links", %{analysis: analysis} do
      result = ContextDocsGenerator.generate(analysis)
      {_, index_content} = Enum.find(result, fn {name, _} -> name == "_index.md" end)

      assert String.contains?(index_content, "Context Documentation Index")
    end
  end
end
