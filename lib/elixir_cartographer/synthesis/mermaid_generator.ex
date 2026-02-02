defmodule ElixirCartographer.Synthesis.MermaidGenerator do
  @moduledoc """
  Generates Mermaid diagrams for visual architecture maps.

  Produces four diagram types:
  - Supervision tree (`graph TD`)
  - Schema ERD (`erDiagram`)
  - Context dependency graph (`graph LR`)
  - Workflow state diagrams (`stateDiagram-v2`)
  """

  @doc """
  Generate a supervision tree diagram from process architecture data.
  """
  def supervision_tree(processes) do
    supervisors = processes.supervisors

    if supervisors == [] do
      ""
    else
      lines =
        supervisors
        |> Enum.flat_map(fn s ->
          parent = sanitize_id(s.module)

          s.children
          |> Enum.map(fn child ->
            child_id = sanitize_id(child)
            "    #{parent} --> #{child_id}"
          end)
        end)

      if lines == [] do
        ""
      else
        """
        ```mermaid
        graph TD
        #{Enum.join(lines, "\n")}
        ```
        """
        |> String.trim_trailing()
      end
    end
  end

  @doc """
  Generate an ERD diagram from Ecto schema data.
  """
  def schema_erd(schemas) do
    if schemas == [] do
      ""
    else
      # Build a set of schema module names for lookup
      schema_modules = MapSet.new(schemas, & &1.module)

      relations =
        schemas
        |> Enum.flat_map(fn s ->
          s.associations
          |> Enum.filter(fn a ->
            # Only include relations where target is a known schema
            target_name = to_string(a.target)
            Enum.any?(schema_modules, fn m -> String.ends_with?(m, ".#{target_name}") || m == target_name end)
          end)
          |> Enum.map(fn a ->
            source = short_name(s.module)
            target = to_string(a.target)
            # Resolve target to short name if it's a full module
            target = short_name(target)

            cardinality = case a.type do
              :has_many -> "||--o{"
              :has_one -> "||--||"
              :belongs_to -> "}o--||"
              :many_to_many -> "}o--o{"
              _ -> "||--o{"
            end

            "    #{source} #{cardinality} #{target} : #{a.type}"
          end)
        end)

      if relations == [] do
        ""
      else
        unique_relations = Enum.uniq(relations)

        """
        ```mermaid
        erDiagram
        #{Enum.join(unique_relations, "\n")}
        ```
        """
        |> String.trim_trailing()
      end
    end
  end

  @doc """
  Generate a context dependency graph from module graph data.
  """
  def context_graph(module_graph) do
    contexts = module_graph.contexts
    edges = module_graph.edges

    if map_size(contexts) < 2 do
      ""
    else
      # Build a module-to-context lookup
      module_to_context =
        contexts
        |> Enum.flat_map(fn {context_name, modules} ->
          Enum.map(modules, fn mod -> {mod, context_name} end)
        end)
        |> Map.new()

      # Find cross-context edges
      cross_context =
        edges
        |> Enum.map(fn edge ->
          from_ctx = Map.get(module_to_context, edge.from)
          to_ctx = Map.get(module_to_context, edge.to)
          {from_ctx, to_ctx}
        end)
        |> Enum.filter(fn {from, to} -> from != nil and to != nil and from != to end)
        |> Enum.uniq()
        |> Enum.map(fn {from, to} ->
          "    #{sanitize_id(from)} --> #{sanitize_id(to)}"
        end)

      if cross_context == [] do
        ""
      else
        """
        ```mermaid
        graph LR
        #{Enum.join(cross_context, "\n")}
        ```
        """
        |> String.trim_trailing()
      end
    end
  end

  @doc """
  Generate a state diagram for a single workflow.
  """
  def workflow_diagram(workflow) do
    values = workflow.status_values

    if values == [] do
      ""
    else
      # Build transitions as sequential: first value is initial state
      transitions =
        values
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [from, to] ->
          "    #{sanitize_state(from)} --> #{sanitize_state(to)}"
        end)

      initial = "    [*] --> #{sanitize_state(List.first(values))}"

      """
      ```mermaid
      stateDiagram-v2
      #{initial}
      #{Enum.join(transitions, "\n")}
      ```
      """
      |> String.trim_trailing()
    end
  end

  @doc """
  Generate all workflow diagrams from a list of workflows.
  """
  def workflow_diagrams(workflows) do
    workflows
    |> Enum.map(fn w ->
      diagram = workflow_diagram(w)
      if diagram != "" do
        "**#{w.module}:**\n\n#{diagram}"
      else
        ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # Sanitize a module name for use as a Mermaid node ID
  defp sanitize_id(name) do
    name
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  # Sanitize a state value for use in stateDiagram
  defp sanitize_state(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  # Get the short name from a fully qualified module name
  defp short_name(module) do
    module
    |> to_string()
    |> String.split(".")
    |> List.last()
  end
end
