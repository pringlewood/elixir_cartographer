defmodule ElixirCartographer.Analyzers.ProcessArchitectureTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.ProcessArchitecture

  setup do
    # Parse both GenServer and Supervisor fixtures
    gs_path = Path.expand("../../fixtures/sample_genserver.ex", __DIR__)
    sup_path = Path.expand("../../fixtures/sample_supervisor.ex", __DIR__)

    gs_content = File.read!(gs_path)
    sup_content = File.read!(sup_path)

    {:ok, gs_ast} = Code.string_to_quoted(gs_content, file: gs_path)
    {:ok, sup_ast} = Code.string_to_quoted(sup_content, file: sup_path)

    parsed = %{
      gs_path => %{ast: gs_ast, content: gs_content},
      sup_path => %{ast: sup_ast, content: sup_content}
    }

    {:ok, parsed: parsed}
  end

  describe "analyze/1" do
    test "detects GenServers", %{parsed: parsed} do
      result = ProcessArchitecture.analyze(parsed)
      assert length(result.genservers) >= 1

      gs = Enum.find(result.genservers, &(&1.module == "SampleApp.Workers.CacheServer"))
      assert gs != nil
    end

    test "extracts GenServer callbacks", %{parsed: parsed} do
      result = ProcessArchitecture.analyze(parsed)
      gs = Enum.find(result.genservers, &(&1.module == "SampleApp.Workers.CacheServer"))

      assert :init in gs.callbacks
      assert :handle_call in gs.callbacks
      assert :handle_cast in gs.callbacks
      assert :handle_info in gs.callbacks
    end

    test "detects Supervisors", %{parsed: parsed} do
      result = ProcessArchitecture.analyze(parsed)
      assert length(result.supervisors) >= 1

      sup = Enum.find(result.supervisors, &(&1.module == "SampleApp.Application"))
      assert sup != nil
    end

    test "extracts supervisor children", %{parsed: parsed} do
      result = ProcessArchitecture.analyze(parsed)
      sup = Enum.find(result.supervisors, &(&1.module == "SampleApp.Application"))

      assert "SampleApp.Workers.CacheServer" in sup.children
      assert "SampleApp.Workers.TaskRunner" in sup.children
    end

    test "handles empty input" do
      result = ProcessArchitecture.analyze(%{})
      assert result.genservers == []
      assert result.supervisors == []
    end
  end
end
