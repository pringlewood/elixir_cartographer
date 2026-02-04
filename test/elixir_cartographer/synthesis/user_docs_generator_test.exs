defmodule ElixirCartographer.Synthesis.UserDocsGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.UserDocsGenerator

  describe "generate/1" do
    test "generates a markdown document with title section" do
      analysis = build_analysis()
      result = UserDocsGenerator.generate(analysis)

      assert result =~ "# Test Project — User Guide"
      assert result =~ "Last generated:"
    end

    test "includes overview section with stats" do
      analysis = build_analysis()
      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Overview"
    end

    test "generates workflows section with mermaid diagrams" do
      analysis =
        build_analysis(
          workflows: [
            %{
              module: "MyApp.Incidents.Incident",
              status_fields: [%{name: :status, type: :string}],
              status_values: ["triggered", "acknowledged", "resolved"],
              transitions: [
                %{function: "def acknowledge(incident)", path: "lib/incidents.ex", context: "MyApp.Incidents", values: ["triggered", "acknowledged"]}
              ],
              branches: 2,
              table: "incidents"
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Workflows & States"
      assert result =~ "### Incident Workflow"
      assert result =~ "Triggered"
      assert result =~ "Acknowledged"
      assert result =~ "Resolved"
      assert result =~ "```mermaid"
      assert result =~ "stateDiagram-v2"
    end

    test "generates data concepts from schemas" do
      analysis =
        build_analysis(
          schemas: [
            %{
              module: "MyApp.Accounts.User",
              table: "users",
              fields: [
                %{name: :id, type: :integer},
                %{name: :email, type: :string},
                %{name: :name, type: :string},
                %{name: :inserted_at, type: :utc_datetime}
              ],
              associations: [
                %{type: :has_many, target: :incidents}
              ]
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Data Concepts"
      assert result =~ "### User"
      assert result =~ "**Email** (text)"
      assert result =~ "**Name** (text)"
      assert result =~ "Has multiple"
    end

    test "generates features from routes" do
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

      assert result =~ "## Features"
      assert result =~ "### User"
      assert result =~ "View list"
      assert result =~ "View details"
      assert result =~ "Save new"
    end

    test "generates pages from LiveViews" do
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

      assert result =~ "## Pages & Screens"
      assert result =~ "### Dashboard"
      assert result =~ "An interactive page"
      assert result =~ "Filter changed"
      assert result =~ "Refresh"
    end

    test "generates navigation map from routes" do
      analysis =
        build_analysis(
          routes: %{
            routes: [
              %{method: "GET", path: "/admin/users", controller: "Admin.UserController", action: "index"},
              %{method: "GET", path: "/api/v1/data", controller: "Api.DataController", action: "index"}
            ],
            pipelines: [],
            scopes: [
              %{path: "/admin", module: nil, as: nil},
              %{path: "/api/v1", module: nil, as: nil}
            ],
            plugs: []
          }
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Navigation Map"
      assert result =~ "### Admin"
      assert result =~ "/admin/users"
    end

    test "generates glossary section" do
      analysis =
        build_analysis(
          schemas: [
            %{
              module: "MyApp.Incidents.Incident",
              table: "incidents",
              fields: [%{name: :id, type: :integer}],
              associations: []
            }
          ],
          workflows: [
            %{
              module: "MyApp.Incidents.Incident",
              status_fields: [%{name: :status, type: :string}],
              status_values: ["pending", "resolved"],
              transitions: [],
              branches: 0,
              table: "incidents"
            }
          ]
        )

      result = UserDocsGenerator.generate(analysis)

      assert result =~ "## Glossary"
      assert result =~ "**Incident**"
      assert result =~ "**Pending**"
      assert result =~ "**Resolved**"
    end

    test "skips sections when no data available" do
      analysis = build_analysis(
        workflows: [],
        schemas: [],
        routes: %{routes: [], pipelines: [], scopes: [], plugs: []},
        live_view: %{live_views: [], live_components: [], function_components: []}
      )

      result = UserDocsGenerator.generate(analysis)

      # Should still have overview
      assert result =~ "## Overview"
      # Should not have empty sections
      refute result =~ "## Workflows & States"
      refute result =~ "## Data Concepts"
      refute result =~ "## Features"
      refute result =~ "## Pages & Screens"
    end
  end

  describe "state explanations" do
    test "provides meaningful explanations for common states" do
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
      assert result =~ "Currently being worked on"
      assert result =~ "Successfully finished"
      assert result =~ "Something went wrong"
      assert result =~ "Stopped by user request"
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
      git: %{total_commits: 0, hotspots: []},
      tests: %{total_tests: 0, test_files: []}
    ]

    Enum.into(overrides, Map.new(defaults))
  end
end
