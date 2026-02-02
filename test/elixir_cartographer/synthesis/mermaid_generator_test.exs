defmodule ElixirCartographer.Synthesis.MermaidGeneratorTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Synthesis.MermaidGenerator

  describe "supervision_tree/1" do
    test "generates valid graph TD Mermaid from supervisors" do
      processes = %ElixirCartographer.Analyzers.ProcessArchitecture{
        supervisors: [
          %{
            module: "MyApp.Supervisor",
            type: :supervisor,
            strategy: :one_for_one,
            children: ["MyApp.Repo", "MyApp.Endpoint", "MyApp.TaskSupervisor"]
          }
        ],
        genservers: [],
        agents: [],
        tasks: [],
        broadway: []
      }

      result = MermaidGenerator.supervision_tree(processes)

      assert String.contains?(result, "```mermaid")
      assert String.contains?(result, "graph TD")
      assert String.contains?(result, "MyApp_Supervisor --> MyApp_Repo")
      assert String.contains?(result, "MyApp_Supervisor --> MyApp_Endpoint")
      assert String.contains?(result, "MyApp_Supervisor --> MyApp_TaskSupervisor")
      assert String.contains?(result, "```")
    end

    test "returns empty string for no supervisors" do
      processes = %ElixirCartographer.Analyzers.ProcessArchitecture{
        supervisors: [],
        genservers: [],
        agents: [],
        tasks: [],
        broadway: []
      }

      assert MermaidGenerator.supervision_tree(processes) == ""
    end

    test "handles multiple supervisors" do
      processes = %ElixirCartographer.Analyzers.ProcessArchitecture{
        supervisors: [
          %{module: "App.Supervisor", type: :supervisor, strategy: :one_for_one, children: ["App.Repo"]},
          %{module: "App.TaskSup", type: :supervisor, strategy: :one_for_one, children: ["App.Worker"]}
        ],
        genservers: [],
        agents: [],
        tasks: [],
        broadway: []
      }

      result = MermaidGenerator.supervision_tree(processes)
      assert String.contains?(result, "App_Supervisor --> App_Repo")
      assert String.contains?(result, "App_TaskSup --> App_Worker")
    end
  end

  describe "schema_erd/1" do
    test "generates valid erDiagram Mermaid from schemas" do
      schemas = [
        %{
          module: "MyApp.Accounts.User",
          table: "users",
          type: :schema,
          fields: [%{name: :id, type: :id}, %{name: :email, type: :string}],
          associations: [%{type: :has_many, name: :posts, target: "Post"}],
          changesets: []
        },
        %{
          module: "MyApp.Blog.Post",
          table: "posts",
          type: :schema,
          fields: [%{name: :id, type: :id}, %{name: :title, type: :string}],
          associations: [%{type: :belongs_to, name: :user, target: "User"}],
          changesets: []
        }
      ]

      result = MermaidGenerator.schema_erd(schemas)

      assert String.contains?(result, "```mermaid")
      assert String.contains?(result, "erDiagram")
      assert String.contains?(result, "User ||--o{ Post : has_many")
      assert String.contains?(result, "```")
    end

    test "returns empty string for no schemas" do
      assert MermaidGenerator.schema_erd([]) == ""
    end

    test "returns empty string when no associations exist" do
      schemas = [
        %{
          module: "MyApp.User",
          table: "users",
          type: :schema,
          fields: [%{name: :id, type: :id}],
          associations: [],
          changesets: []
        }
      ]

      assert MermaidGenerator.schema_erd(schemas) == ""
    end

    test "handles has_one associations" do
      schemas = [
        %{
          module: "MyApp.User",
          table: "users",
          type: :schema,
          fields: [],
          associations: [%{type: :has_one, name: :profile, target: "Profile"}],
          changesets: []
        },
        %{
          module: "MyApp.Profile",
          table: "profiles",
          type: :schema,
          fields: [],
          associations: [%{type: :belongs_to, name: :user, target: "User"}],
          changesets: []
        }
      ]

      result = MermaidGenerator.schema_erd(schemas)
      assert String.contains?(result, "User ||--|| Profile : has_one")
    end
  end

  describe "context_graph/1" do
    test "generates valid graph LR Mermaid from cross-context edges" do
      module_graph = %ElixirCartographer.Analyzers.ModuleGraph{
        modules: %{
          "MyApp.Accounts" => %{name: "MyApp.Accounts"},
          "MyApp.Orders" => %{name: "MyApp.Orders"}
        },
        contexts: %{
          "Accounts" => ["MyApp.Accounts", "MyApp.Accounts.User"],
          "Orders" => ["MyApp.Orders", "MyApp.Orders.Order"]
        },
        edges: [
          %{from: "MyApp.Orders", to: "MyApp.Accounts", type: :alias}
        ]
      }

      result = MermaidGenerator.context_graph(module_graph)

      assert String.contains?(result, "```mermaid")
      assert String.contains?(result, "graph LR")
      assert String.contains?(result, "Orders --> Accounts")
      assert String.contains?(result, "```")
    end

    test "returns empty string for fewer than 2 contexts" do
      module_graph = %ElixirCartographer.Analyzers.ModuleGraph{
        modules: %{},
        contexts: %{"Single" => ["MyApp.Single"]},
        edges: []
      }

      assert MermaidGenerator.context_graph(module_graph) == ""
    end

    test "returns empty string when no cross-context edges" do
      module_graph = %ElixirCartographer.Analyzers.ModuleGraph{
        modules: %{},
        contexts: %{
          "Accounts" => ["MyApp.Accounts"],
          "Orders" => ["MyApp.Orders"]
        },
        edges: [
          %{from: "MyApp.Accounts", to: "MyApp.Accounts.User", type: :alias}
        ]
      }

      assert MermaidGenerator.context_graph(module_graph) == ""
    end
  end

  describe "workflow_diagram/1" do
    test "generates valid stateDiagram-v2 Mermaid" do
      workflow = %{
        module: "MyApp.Order",
        table: "orders",
        status_fields: [%{name: :status, type: :string}],
        status_values: ["pending", "active", "suspended", "archived"],
        transitions: [],
        branches: 3
      }

      result = MermaidGenerator.workflow_diagram(workflow)

      assert String.contains?(result, "```mermaid")
      assert String.contains?(result, "stateDiagram-v2")
      assert String.contains?(result, "[*] --> pending")
      assert String.contains?(result, "pending --> active")
      assert String.contains?(result, "active --> suspended")
      assert String.contains?(result, "suspended --> archived")
      assert String.contains?(result, "```")
    end

    test "returns empty string for workflow with no status values" do
      workflow = %{
        module: "MyApp.Order",
        table: "orders",
        status_fields: [],
        status_values: [],
        transitions: [],
        branches: 0
      }

      assert MermaidGenerator.workflow_diagram(workflow) == ""
    end
  end

  describe "workflow_diagrams/1" do
    test "generates diagrams for multiple workflows" do
      workflows = [
        %{
          module: "MyApp.Order",
          table: "orders",
          status_fields: [%{name: :status, type: :string}],
          status_values: ["pending", "active"],
          transitions: [],
          branches: 1
        },
        %{
          module: "MyApp.Task",
          table: "tasks",
          status_fields: [%{name: :state, type: :string}],
          status_values: ["open", "closed"],
          transitions: [],
          branches: 1
        }
      ]

      result = MermaidGenerator.workflow_diagrams(workflows)
      assert String.contains?(result, "MyApp.Order")
      assert String.contains?(result, "MyApp.Task")
      assert String.contains?(result, "pending --> active")
      assert String.contains?(result, "open --> closed")
    end

    test "returns empty string for empty workflows" do
      assert MermaidGenerator.workflow_diagrams([]) == ""
    end

    test "skips workflows with no status values" do
      workflows = [
        %{
          module: "MyApp.Empty",
          table: "empty",
          status_fields: [],
          status_values: [],
          transitions: [],
          branches: 0
        }
      ]

      assert MermaidGenerator.workflow_diagrams(workflows) == ""
    end
  end
end
