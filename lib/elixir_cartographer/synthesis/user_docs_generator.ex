defmodule ElixirCartographer.Synthesis.UserDocsGenerator do
  @moduledoc """
  Generates end-user documentation from an Elixir codebase.

  Focus: What can users DO? How do things work? What do terms mean?
  No code details, no field types, no schema internals.
  """

  @doc """
  Generate USER_DOCS.md - documentation for end users, not developers.
  """
  def generate(analysis) do
    project_name = format_project_name(analysis.config.project_name)
    docs_lookup = Map.get(analysis, :docs_lookup, %{})

    [
      title_section(project_name),
      what_is_section(analysis, docs_lookup),
      what_you_can_do_section(analysis, docs_lookup),
      how_it_works_section(analysis, docs_lookup),
      user_roles_section(analysis),
      key_concepts_section(analysis, docs_lookup)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  # ---------------------------------------------------------------------------
  # Title
  # ---------------------------------------------------------------------------

  defp title_section(project_name) do
    """
    # #{project_name} — User Guide

    This guide explains what you can do with #{project_name} and how it works.
    """
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # What Is This System?
  # ---------------------------------------------------------------------------

  defp what_is_section(analysis, docs_lookup) do
    # Try to find a top-level module doc that describes the app
    app_description = find_app_description(analysis, docs_lookup)

    capabilities = summarize_capabilities(analysis)

    """
    ## What is #{format_project_name(analysis.config.project_name)}?

    #{app_description}

    #{capabilities}
    """
    |> String.trim()
  end

  defp find_app_description(analysis, docs_lookup) do
    # Look for application module or main context docs
    project_name = analysis.config.project_name

    # Try different module name patterns
    candidates = [
      project_name |> Macro.camelize(),
      "#{Macro.camelize(project_name)}Web",
      "#{Macro.camelize(project_name)}.Application"
    ]

    description =
      candidates
      |> Enum.find_value(fn candidate ->
        case Map.get(docs_lookup, candidate) do
          %{module_doc: %{summary: summary}} when is_binary(summary) and summary != "" ->
            unless generic_doc?(summary), do: summary
          _ -> nil
        end
      end)

    description || "A web application built with Elixir and Phoenix."
  end

  defp summarize_capabilities(analysis) do
    parts = []

    # Count main features
    live_views = length(analysis.live_view.live_views)
    routes = length(analysis.routes.routes)
    workflows = analysis.workflows |> Enum.filter(fn w -> length(w.status_values) >= 2 end) |> length()

    parts = if live_views > 0, do: parts ++ ["#{live_views} interactive screens"], else: parts
    parts = if workflows > 0, do: parts ++ ["#{workflows} tracked workflows"], else: parts

    if parts == [] do
      ""
    else
      "**At a glance:** " <> Enum.join(parts, ", ") <> "."
    end
  end

  # ---------------------------------------------------------------------------
  # What You Can Do
  # ---------------------------------------------------------------------------

  defp what_you_can_do_section(analysis, docs_lookup) do
    actions = extract_user_actions(analysis, docs_lookup)

    if actions == [] do
      nil
    else
      action_docs =
        actions
        |> Enum.group_by(& &1.area)
        |> Enum.sort_by(fn {area, _} -> area end)
        |> Enum.map(fn {area, area_actions} ->
          action_list =
            area_actions
            |> Enum.map(fn a -> "- #{a.description}" end)
            |> Enum.uniq()
            |> Enum.join("\n")

          "### #{area}\n\n#{action_list}"
        end)
        |> Enum.join("\n\n")

      """
      ## What You Can Do

      #{action_docs}
      """
      |> String.trim()
    end
  end

  defp extract_user_actions(analysis, docs_lookup) do
    # From routes - each route is something a user can do
    route_actions =
      analysis.routes.routes
      |> Enum.map(fn route ->
        area = humanize_controller(route.controller)
        action_name = route.action |> to_string()

        # Try to get @doc for this action
        doc = find_function_doc(route.controller, action_name, docs_lookup)

        description = doc || action_to_description(action_name, area)

        %{area: area, action: action_name, description: description}
      end)
      |> Enum.uniq_by(fn a -> {a.area, a.action} end)

    # From LiveView events - user interactions
    event_actions =
      analysis.live_view.live_views
      |> Enum.flat_map(fn lv ->
        area = humanize_module(short_name(lv.module))
        events = Map.get(lv, :events, [])

        Enum.map(events, fn event ->
          %{
            area: area,
            action: event,
            description: event_to_description(event)
          }
        end)
      end)

    (route_actions ++ event_actions)
    |> Enum.uniq_by(fn a -> {a.area, a.description} end)
  end

  defp action_to_description(action, area) do
    area_lower = String.downcase(area)
    area_plural = pluralize(area_lower)

    case to_string(action) do
      "index" -> "View all #{area_plural}"
      "show" -> "View #{area_lower} details"
      "new" -> "Create a new #{area_lower}"
      "create" -> "Save a new #{area_lower}"
      "edit" -> "Edit an existing #{area_lower}"
      "update" -> "Save changes to a #{area_lower}"
      "delete" -> "Remove a #{area_lower}"
      "acknowledge" -> "Acknowledge (confirm you're handling it)"
      "resolve" -> "Mark as resolved"
      "escalate" -> "Escalate to the next person"
      "export" -> "Export data"
      "import" -> "Import data"
      "search" -> "Search #{area_lower}s"
      "filter" -> "Filter the list"
      other -> humanize_action_name(other)
    end
  end

  defp event_to_description(event) do
    event
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.capitalize()
  end

  defp humanize_action_name(action) do
    action
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # ---------------------------------------------------------------------------
  # How It Works (Workflows)
  # ---------------------------------------------------------------------------

  defp how_it_works_section(analysis, docs_lookup) do
    workflows = analysis.workflows |> Enum.filter(fn w -> length(w.status_values) >= 2 end)

    if workflows == [] do
      nil
    else
      workflow_docs =
        workflows
        |> Enum.map(fn w -> format_workflow_for_users(w, docs_lookup) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      if workflow_docs == "" do
        nil
      else
        """
        ## How Things Work

        #{workflow_docs}
        """
        |> String.trim()
      end
    end
  end

  defp format_workflow_for_users(workflow, docs_lookup) do
    name = workflow.module |> short_name() |> humanize_module()
    states = workflow.status_values

    # Get module doc for context
    module_doc = find_module_summary(workflow.module, docs_lookup)
    intro = module_doc || "#{name}s go through several stages:"

    # Describe the journey
    journey =
      states
      |> Enum.with_index()
      |> Enum.map(fn {state, idx} ->
        state_name = humanize_state(state)
        explanation = explain_state_for_users(state)

        if idx == 0 do
          "1. **#{state_name}** — #{explanation}"
        else
          "#{idx + 1}. **#{state_name}** — #{explanation}"
        end
      end)
      |> Enum.join("\n")

    # Simple mermaid diagram
    diagram = generate_simple_flow(states)

    """
    ### #{name}

    #{intro}

    #{journey}

    #{diagram}
    """
    |> String.trim()
  end

  defp generate_simple_flow(states) do
    if length(states) < 2 do
      ""
    else
      transitions =
        states
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [from, to] ->
          "    #{safe_id(from)} --> #{safe_id(to)}"
        end)
        |> Enum.join("\n")

      """
      ```mermaid
      flowchart LR
      #{transitions}
      ```
      """
      |> String.trim()
    end
  end

  defp safe_id(state) do
    state |> to_string() |> String.replace(~r/[^a-zA-Z0-9]/, "_")
  end

  defp explain_state_for_users(state) do
    state_lower = to_string(state) |> String.downcase()

    cond do
      state_lower in ~w(triggered new open created) ->
        "Just happened, waiting for someone to respond"
      state_lower in ~w(acknowledged acked accepted) ->
        "Someone is working on it"
      state_lower in ~w(resolved closed completed done finished) ->
        "All done"
      state_lower in ~w(pending waiting queued) ->
        "Waiting to be processed"
      state_lower in ~w(active running in_progress processing) ->
        "Currently in progress"
      state_lower in ~w(cancelled canceled rejected declined) ->
        "Was stopped or rejected"
      state_lower in ~w(failed error) ->
        "Something went wrong"
      state_lower in ~w(draft) ->
        "Work in progress, not yet submitted"
      state_lower in ~w(published live) ->
        "Visible and active"
      state_lower in ~w(archived) ->
        "Stored for reference, no longer active"
      state_lower in ~w(scheduled) ->
        "Planned for a future time"
      state_lower in ~w(paused suspended on_hold) ->
        "Temporarily stopped"
      state_lower in ~w(investigating) ->
        "Looking into the issue"
      state_lower in ~w(identified) ->
        "Found the cause"
      state_lower in ~w(monitoring) ->
        "Watching to make sure it's fixed"
      state_lower in ~w(sent delivered) ->
        "Message has been sent"
      state_lower in ~w(expired) ->
        "No longer valid"
      true ->
        "In #{humanize_state(state)} stage"
    end
  end

  # ---------------------------------------------------------------------------
  # User Roles
  # ---------------------------------------------------------------------------

  defp user_roles_section(analysis) do
    roles_data = Map.get(analysis, :roles, %{roles: [], role_capabilities: []})

    all_roles =
      roles_data.roles
      |> Enum.flat_map(& &1.values)
      |> Enum.uniq()

    if all_roles == [] do
      nil
    else
      capabilities_map =
        Map.get(roles_data, :role_capabilities, [])
        |> Enum.into(%{}, fn cap -> {cap.role, cap} end)

      role_docs =
        all_roles
        |> Enum.map(fn role ->
          cap = Map.get(capabilities_map, role)
          format_role_for_users(role, cap)
        end)
        |> Enum.join("\n\n")

      """
      ## User Roles

      Different users have different levels of access:

      #{role_docs}
      """
      |> String.trim()
    end
  end

  defp format_role_for_users(role, nil) do
    "- **#{String.capitalize(role)}** — Has access to the system."
  end

  defp format_role_for_users(role, %{can: can, cannot: cannot}) do
    base = "- **#{String.capitalize(role)}**"

    cond do
      can != [] && cannot != [] ->
        can_text = can |> Enum.map(&String.capitalize/1) |> Enum.join(", ")
        cannot_text = cannot |> Enum.map(&String.capitalize/1) |> Enum.join(", ")
        "#{base} — Can: #{can_text}. Cannot: #{cannot_text}."

      can != [] ->
        can_text = can |> Enum.map(&String.capitalize/1) |> Enum.join(", ")
        "#{base} — Can: #{can_text}."

      cannot != [] ->
        cannot_text = cannot |> Enum.map(&String.capitalize/1) |> Enum.join(", ")
        "#{base} — Cannot: #{cannot_text}."

      true ->
        "#{base} — Has access to the system."
    end
  end

  # ---------------------------------------------------------------------------
  # Key Concepts
  # ---------------------------------------------------------------------------

  defp key_concepts_section(analysis, docs_lookup) do
    # Extract meaningful concepts from schemas (not all, just the main ones)
    concepts =
      analysis.schemas
      |> Enum.map(fn schema ->
        name = schema.module |> short_name() |> humanize_module()
        description = find_concept_description(schema.module, docs_lookup)
        %{name: name, description: description}
      end)
      |> Enum.filter(fn c -> c.description != nil end)
      |> Enum.take(15)

    if concepts == [] do
      nil
    else
      concept_list =
        concepts
        |> Enum.map(fn c -> "- **#{c.name}** — #{c.description}" end)
        |> Enum.join("\n")

      """
      ## Key Concepts

      #{concept_list}
      """
      |> String.trim()
    end
  end

  defp find_concept_description(module_name, docs_lookup) do
    # Look for @moduledoc that describes this concept
    summary = find_module_summary(module_name, docs_lookup)

    cond do
      summary != nil && !generic_doc?(summary) ->
        # Clean up the summary for end users
        summary
        |> String.replace(~r/^The \w+ context[.\s]*/, "")
        |> String.replace(~r/Ecto schema for /, "")
        |> String.trim()
        |> case do
          "" -> nil
          cleaned -> cleaned
        end

      true ->
        # Try to infer from the name
        infer_concept_from_name(module_name)
    end
  end

  defp infer_concept_from_name(module_name) do
    name = module_name |> short_name() |> String.downcase()

    cond do
      String.contains?(name, "user") -> "A person who uses the system"
      String.contains?(name, "incident") -> "Something that needs attention or response"
      String.contains?(name, "alert") -> "A notification about something important"
      String.contains?(name, "schedule") -> "Defines when things happen or who is responsible when"
      String.contains?(name, "team") -> "A group of people working together"
      String.contains?(name, "member") -> "A person belonging to a team or organization"
      String.contains?(name, "notification") -> "A message sent to users"
      String.contains?(name, "invitation") -> "An invite to join the system"
      String.contains?(name, "organization") || String.contains?(name, "organisation") ->
        "A company or group that uses the system"
      String.contains?(name, "policy") -> "Rules that define how something works"
      String.contains?(name, "runbook") -> "Step-by-step guide for handling situations"
      String.contains?(name, "escalation") -> "Process of notifying more people if no response"
      true -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_project_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp short_name(module) when is_binary(module) do
    module |> String.split(".") |> List.last()
  end

  defp short_name(module) when is_atom(module) do
    module |> to_string() |> short_name()
  end

  defp humanize_module(name) do
    name
    |> to_string()
    |> String.replace(~r/Live$/, "")
    |> String.replace(~r/Controller$/, "")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.trim()
  end

  defp humanize_controller(name) do
    name
    |> to_string()
    |> String.replace("Controller", "")
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.trim()
  end

  defp humanize_state(state) do
    state
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp pluralize(word) do
    cond do
      String.ends_with?(word, "y") && !String.ends_with?(word, "ey") ->
        String.slice(word, 0..-2//1) <> "ies"
      String.ends_with?(word, "s") || String.ends_with?(word, "x") ||
      String.ends_with?(word, "ch") || String.ends_with?(word, "sh") ->
        word <> "es"
      true ->
        word <> "s"
    end
  end

  defp generic_doc?(doc) do
    Regex.match?(~r/^The \w+ context\.?$/i, doc) ||
    Regex.match?(~r/^Ecto schema for/i, doc) ||
    String.length(doc) < 20
  end

  defp find_module_summary(module_name, docs_lookup) do
    search_name = short_name(module_name)

    matching_key =
      docs_lookup
      |> Map.keys()
      |> Enum.find(fn key ->
        short_name(key) == search_name ||
        String.ends_with?(key, ".#{search_name}")
      end)

    case matching_key && Map.get(docs_lookup, matching_key) do
      %{module_doc: %{summary: summary}} when is_binary(summary) -> summary
      _ -> nil
    end
  end

  defp find_function_doc(controller, action, docs_lookup) do
    # Try to find the controller and its function doc
    search_name = String.replace(controller, "Controller", "")

    matching_key =
      docs_lookup
      |> Map.keys()
      |> Enum.find(fn key -> String.contains?(key, search_name) end)

    case matching_key && Map.get(docs_lookup, matching_key) do
      %{functions: functions} ->
        case Enum.find(functions, fn f -> f.function == action end) do
          %{summary: summary} -> clean_doc_for_users(summary)
          _ -> nil
        end
      _ -> nil
    end
  end

  # Clean up docs to remove code snippets and technical details
  defp clean_doc_for_users(nil), do: nil
  defp clean_doc_for_users(doc) do
    cleaned =
      doc
      |> String.split(~r/\n\n|"""|\bdef\b|\bdefp\b/, parts: 2)
      |> List.first()
      |> String.replace(~r/`[^`]+`/, "")  # Remove inline code
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if String.length(cleaned) > 10 && !String.contains?(cleaned, "defp") do
      cleaned
    else
      nil
    end
  end
end
