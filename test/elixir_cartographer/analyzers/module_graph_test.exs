defmodule ElixirCartographer.Analyzers.ModuleGraphTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.ModuleGraph

  @fixture_path Path.expand("../../fixtures/sample_module.ex", __DIR__)

  setup do
    content = File.read!(@fixture_path)
    {:ok, ast} = Code.string_to_quoted(content, file: @fixture_path, columns: true)
    parsed = %{@fixture_path => %{ast: ast, content: content}}
    {:ok, parsed: parsed}
  end

  describe "analyze/1" do
    test "extracts module names", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      assert Map.has_key?(result.modules, "SampleApp.Accounts.User")
    end

    test "extracts public functions", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      user_mod = result.modules["SampleApp.Accounts.User"]
      pub_names = Enum.map(user_mod.public_functions, & &1.name)

      assert :changeset in pub_names
      assert :registration_changeset in pub_names
      assert :activate in pub_names
      assert :deactivate in pub_names
      assert :suspend in pub_names
    end

    test "extracts private functions", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      user_mod = result.modules["SampleApp.Accounts.User"]
      priv_names = Enum.map(user_mod.private_functions, & &1.name)

      assert :change_status in priv_names
    end

    test "extracts use declarations", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      user_mod = result.modules["SampleApp.Accounts.User"]

      assert "Ecto.Schema" in user_mod.uses
    end

    test "extracts imports", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      user_mod = result.modules["SampleApp.Accounts.User"]

      assert "Ecto.Changeset" in user_mod.imports
    end

    test "extracts aliases", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      user_mod = result.modules["SampleApp.Accounts.User"]

      assert "SampleApp.Accounts.Role" in user_mod.aliases
      assert "SampleApp.Organizations.Organization" in user_mod.aliases
    end

    test "builds edges between modules", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)

      assert Enum.any?(result.edges, fn edge ->
        edge.from == "SampleApp.Accounts.User" &&
          edge.to == "Ecto.Schema" &&
          edge.type == :use
      end)
    end

    test "detects contexts", %{parsed: parsed} do
      result = ModuleGraph.analyze(parsed)
      assert Map.has_key?(result.contexts, "Accounts")
    end
  end

  describe "detect_contexts/1" do
    test "groups modules by namespace" do
      modules = %{
        "App.Accounts.User" => %{},
        "App.Accounts.Auth" => %{},
        "App.Orders.Order" => %{},
        "App.Orders.Item" => %{}
      }

      contexts = ModuleGraph.detect_contexts(modules)

      assert "Accounts" in Map.keys(contexts)
      assert "Orders" in Map.keys(contexts)
      assert length(contexts["Accounts"]) == 2
      assert length(contexts["Orders"]) == 2
    end
  end

  describe "handles malformed ASTs" do
    test "returns empty for nil ASTs" do
      parsed = %{"bad.ex" => %{ast: nil, content: ""}}
      result = ModuleGraph.analyze(parsed)
      assert result.modules == %{}
    end

    test "handles empty parsed files" do
      result = ModuleGraph.analyze(%{})
      assert result.modules == %{}
      assert result.edges == []
    end
  end
end
