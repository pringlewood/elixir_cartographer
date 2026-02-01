defmodule ElixirCartographer.Analyzers.RouteMapperTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.RouteMapper
  alias ElixirCartographer.Config

  @fixture_path Path.expand("../../fixtures/sample_router.ex", __DIR__)

  setup do
    content = File.read!(@fixture_path)
    {:ok, ast} = Code.string_to_quoted(content, file: @fixture_path)
    parsed = %{@fixture_path => %{ast: ast, content: content}}
    config = Config.new(Path.expand("../../fixtures", __DIR__))
    {:ok, parsed: parsed, config: config}
  end

  describe "analyze/2" do
    test "extracts HTTP routes", %{parsed: parsed, config: config} do
      result = RouteMapper.analyze(parsed, config)

      assert Enum.any?(result.routes, fn r ->
        r.method == "GET" && r.path == "/" && r.action == "index"
      end)

      assert Enum.any?(result.routes, fn r ->
        r.method == "POST" && r.path == "/users" && r.controller == "UserController"
      end)
    end

    test "extracts all CRUD routes", %{parsed: parsed, config: config} do
      result = RouteMapper.analyze(parsed, config)
      methods = Enum.map(result.routes, & &1.method) |> Enum.uniq()

      assert "GET" in methods
      assert "POST" in methods
      assert "PUT" in methods
      assert "DELETE" in methods
    end

    test "extracts pipelines", %{parsed: parsed, config: config} do
      result = RouteMapper.analyze(parsed, config)

      assert Enum.any?(result.pipelines, &(&1.name == "browser"))
      assert Enum.any?(result.pipelines, &(&1.name == "api"))
    end

    test "extracts pipeline plugs", %{parsed: parsed, config: config} do
      result = RouteMapper.analyze(parsed, config)
      api_pipeline = Enum.find(result.pipelines, &(&1.name == "api"))

      assert "accepts" in api_pipeline.plugs
    end

    test "extracts scopes", %{parsed: parsed, config: config} do
      result = RouteMapper.analyze(parsed, config)

      assert Enum.any?(result.scopes, &(&1.path == "/"))
      assert Enum.any?(result.scopes, &(&1.path == "/api/v1"))
      assert Enum.any?(result.scopes, &(&1.path == "/admin"))
    end
  end

  describe "extract_live_routes/1" do
    test "extracts LiveView routes" do
      content = File.read!(@fixture_path)
      routes = RouteMapper.extract_live_routes(content)

      assert Enum.any?(routes, fn r ->
        r.path == "/dashboard" && r.module == "DashboardLive"
      end)

      assert Enum.any?(routes, fn r ->
        r.path == "/users" && r.module == "UsersLive"
      end)
    end

    test "handles content without live routes" do
      routes = RouteMapper.extract_live_routes("get \"/\", PageController, :index")
      assert routes == []
    end
  end
end
