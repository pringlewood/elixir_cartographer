defmodule ElixirCartographer.Synthesis.UserDocsGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.UserDocsGenerator

  describe "generate/1" do
    test "generates a user-friendly markdown document" do
      analysis = build_analysis()
      result = UserDocsGenerator.generate(analysis)

      assert result =~ "# Test Project — User Guide"
      assert result =~ "This guide explains what you can do"
    end

    test "includes what is section" do
      analysis = build_analysis()
      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## What is Test Project?"
    end

    test "generates how it works section with workflows" do
      analysis =
        build_analysis(
          workflows: [
            %{
              module: "MyApp.Incidents.Incident",
              status_fields: [%{name: :status, type: :string}],
              status_values: ["triggered", "acknowledged", "resolved"],
              transitions: [],
              branches: 2,
              table: "incidents"
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## How Things Work"
      assert result =~ "### Incident"
      assert result =~ "Triggered"
      assert result =~ "Acknowledged"
      assert result =~ "Resolved"
      assert result =~ "```mermaid"
      assert result =~ "flowchart LR"
    end

    test "generates what you can do section from routes" do
      analysis =
        build_analysis(
          routes: %{
            routes: [
              %{method: "GET", path: "/users", controller: "UserController", action: "index"},
              %{method: "GET", path: "/users/:id", controller: "UserController", action: "show"},
              %{method: "POST", path: "/users", controller: "UserController", action: "create"}
            ],
            pipelines: [],
            scopes: [],
            plugs: []
          }
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## What You Can Do"
      assert result =~ "### User"
      assert result =~ "View all users"
      assert result =~ "View user details"
      assert result =~ "Save a new user"
    end

    test "generates what you can do section from LiveView events" do
      analysis =
        build_analysis(
          live_view: %{
            live_views: [
              %{
                type: :live_view,
                module: "MyAppWeb.DashboardLive",
                path: "lib/my_app_web/live/dashboard_live.ex",
                callbacks: [:mount, :handle_event, :render],
                events: ["filter_changed", "refresh"]
              }
            ],
            live_components: [],
            function_components: []
          }
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## What You Can Do"
      assert result =~ "Filter changed"
      assert result =~ "Refresh"
    end

    test "generates key concepts section" do
      analysis =
        build_analysis(
          schemas: [
            %{
              module: "MyApp.Incidents.Incident",
              table: "incidents",
              fields: [%{name: :id, type: :integer}],
              associations: []
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Key Concepts"
      assert result =~ "**Incident**"
    end

    test "generates user roles section" do
      analysis = build_analysis()
      result = UserDocsGenerator.generate(analysis)

      # Should not have roles section if no roles defined
      refute result =~ "## User Roles"

      # Add roles
      analysis_with_roles = build_analysis(
        roles: %{
          roles: [%{values: ["admin", "member"], source: :test, context: "Test", path: "test.ex"}],
          permissions: [],
          policies: [],
          auth_plugs: [],
          role_capabilities: []
        }
      )

      result_with_roles = UserDocsGenerator.generate(analysis_with_roles)
      assert result_with_roles =~ "## User Roles"
      assert result_with_roles =~ "**Admin**"
      assert result_with_roles =~ "**Member**"
    end

    test "explains workflow states in user-friendly language" do
      analysis =
        build_analysis(
          workflows: [
            %{
              module: "MyApp.Tasks.Task",
              status_fields: [%{name: :status, type: :string}],
              status_values: ["pending", "active", "completed", "failed", "cancelled"],
              transitions: [],
              branches: 0,
              table: "tasks"
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "Waiting to be processed"
      assert result =~ "Currently in progress"
      assert result =~ "All done"
      assert result =~ "Something went wrong"
      assert result =~ "Was stopped or rejected"
    end

    test "skips sections when no data available" do
      analysis = build_analysis(
        workflows: [],
        schemas: [],
        routes: %{routes: [], pipelines: [], scopes: [], plugs: []},
        live_view: %{live_views: [], live_components: [], function_components: []}
      )

      result = UserDocsGenerator.generate(analysis)

      # Should still have title and what is
      assert result =~ "# Test Project — User Guide"
      assert result =~ "## What is Test Project?"

      # Should not have empty sections
      refute result =~ "## How Things Work"
      refute result =~ "## What You Can Do"
      refute result =~ "## Key Concepts"
    end

    test "pluralizes correctly" do
      analysis =
        build_analysis(
          routes: %{
            routes: [
              %{method: "GET", path: "/policies", controller: "PolicyController", action: "index"},
              %{method: "GET", path: "/categories", controller: "CategoryController", action: "index"}
            ],
            pipelines: [],
            scopes: [],
            plugs: []
          }
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "View all policies"
      assert result =~ "View all categories"
    end
  end

  # Helper to build analysis maps with sensible defaults
  defp build_analysis(overrides \\ []) do
    defaults = [
      config: %{project_name: "test_project", output_path: "/tmp/test"},
      module_graph: %{modules: %{}, contexts: %{}, edges: []},
      schemas: [],
      processes: %{genservers: [], supervisors: []},
      routes: %{routes: [], pipelines: [], scopes: [], plugs: []},
      live_view: %{
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
      },
      config_matrix: %{env_vars: [], app_configs: []},
      errors: [],
      workflows: [],
      roles: %{roles: [], permissions: [], policies: [], auth_plugs: [], role_capabilities: []},
      docs: [],
      docs_lookup: %{},
      git: %{total_commits: 0, hotspots: []},
      tests: %{total_tests: 0, test_files: []}
    ]

    Enum.into(overrides, Map.new(defaults))
  end
end
