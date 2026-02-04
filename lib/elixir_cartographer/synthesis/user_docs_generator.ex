defmodule ElixirCartographer.Synthesis.UserDocsGenerator do
  @moduledoc """
  Generates user-friendly documentation for non-technical audiences.

  Outputs a single markdown file with:
  - Plain English descriptions of features and workflows
  - Mermaid diagrams for visual context
  - State machine explanations
  - Feature inventory for helpdesk/LLM training
  """

  alias ElixirCartographer.Synthesis.MermaidGenerator

  @doc """
  Generate a single USER_DOCS.md file from the analysis data.
  """
  def generate(analysis) do
    project_name = format_project_name(analysis.config.project_name)

    [
      title_section(project_name),
      overview_section(analysis),
      features_section(analysis),
      pages_section(analysis),
      workflows_section(analysis),
      data_concepts_section(analysis),
      navigation_section(analysis),
      glossary_section(analysis)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n---\n\n")
  end

  # ---------------------------------------------------------------------------
  # Section Generators
  # ---------------------------------------------------------------------------

  defp title_section(project_name) do
    """
    # #{project_name} — User Guide

    > This document explains how #{project_name} works in plain language.
    > Use it for onboarding, help desk support, or training AI assistants.

    **Last generated:** #{Date.utc_today() |> Date.to_string()}
    """
    |> String.trim()
  end

  defp overview_section(analysis) do
    stats = gather_stats(analysis)

    """
    ## Overview

    #{project_name(analysis)} is a web application with the following capabilities:

    #{stats_list(stats)}

    This guide walks through each feature and explains how users interact with the system.
    """
    |> String.trim()
  end

  defp features_section(analysis) do
    routes = analysis.routes.routes
    live_views = analysis.live_view.live_views

    if routes == [] && live_views == [] do
      nil
    else
      features = extract_features(routes, live_views, analysis)

      if features == [] do
        nil
      else
        feature_docs =
          features
          |> Enum.map(&format_feature/1)
          |> Enum.join("\n\n")

        """
        ## Features

        Below is a list of the main features available to users.

        #{feature_docs}
        """
        |> String.trim()
      end
    end
  end

  defp pages_section(analysis) do
    live_views = analysis.live_view.live_views

    if live_views == [] do
      nil
    else
      pages =
        live_views
        |> Enum.map(&format_page/1)
        |> Enum.join("\n\n")

      """
      ## Pages & Screens

      The application includes the following interactive pages:

      #{pages}
      """
      |> String.trim()
    end
  end

  defp workflows_section(analysis) do
    workflows = analysis.workflows

    if workflows == [] do
      nil
    else
      workflow_docs =
        workflows
        |> Enum.filter(fn w -> length(w.status_values) >= 2 end)
        |> Enum.map(&format_workflow/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      if workflow_docs == "" do
        nil
      else
        """
        ## Workflows & States

        The system tracks items through different stages. Here's how each workflow operates:

        #{workflow_docs}
        """
        |> String.trim()
      end
    end
  end

  defp data_concepts_section(analysis) do
    schemas = analysis.schemas

    if schemas == [] do
      nil
    else
      concepts =
        schemas
        |> Enum.map(&format_data_concept/1)
        |> Enum.join("\n\n")

      """
      ## Data Concepts

      The system works with the following types of information:

      #{concepts}
      """
      |> String.trim()
    end
  end

  defp navigation_section(analysis) do
    routes = analysis.routes.routes
    scopes = analysis.routes.scopes

    if routes == [] do
      nil
    else
      # Group routes by prefix
      grouped = group_routes_by_area(routes, scopes)

      nav_docs =
        grouped
        |> Enum.map(fn {area, area_routes} ->
          route_list =
            area_routes
            |> Enum.take(10)
            |> Enum.map(fn r -> "  - `#{r.path}` — #{humanize_action(r.action)}" end)
            |> Enum.join("\n")

          "### #{humanize_area(area)}\n\n#{route_list}"
        end)
        |> Enum.join("\n\n")

      """
      ## Navigation Map

      Here's where users can go in the application:

      #{nav_docs}
      """
      |> String.trim()
    end
  end

  defp glossary_section(analysis) do
    terms = extract_glossary_terms(analysis)

    if terms == [] do
      nil
    else
      term_docs =
        terms
        |> Enum.sort_by(& &1.term)
        |> Enum.map(fn t -> "- **#{t.term}**: #{t.definition}" end)
        |> Enum.join("\n")

      """
      ## Glossary

      Key terms used in the application:

      #{term_docs}
      """
      |> String.trim()
    end
  end

  # ---------------------------------------------------------------------------
  # Formatters
  # ---------------------------------------------------------------------------

  defp format_feature(%{name: name, description: desc, actions: actions}) do
    action_list =
      if actions == [] do
        ""
      else
        "\n\n**Available actions:**\n" <>
          (actions |> Enum.map(&("- #{&1}")) |> Enum.join("\n"))
      end

    """
    ### #{name}

    #{desc}#{action_list}
    """
    |> String.trim()
  end

  defp format_page(live_view) do
    module = short_name(live_view.module)
    name = humanize_module(module)

    events =
      if Map.has_key?(live_view, :events) && live_view.events != [] do
        event_list =
          live_view.events
          |> Enum.map(&humanize_event/1)
          |> Enum.join(", ")

        "\n\n**User can:** #{event_list}"
      else
        ""
      end

    callbacks =
      if Map.has_key?(live_view, :callbacks) do
        features =
          live_view.callbacks
          |> Enum.filter(&(&1 in [:handle_event, :handle_info, :handle_params]))
          |> Enum.map(fn
            :handle_event -> "respond to user actions"
            :handle_info -> "receive real-time updates"
            :handle_params -> "react to URL changes"
          end)

        if features != [] do
          "\n\n**Capabilities:** #{Enum.join(features, ", ")}"
        else
          ""
        end
      else
        ""
      end

    """
    ### #{name}

    An interactive page that updates in real-time.#{events}#{callbacks}
    """
    |> String.trim()
  end

  defp format_workflow(workflow) do
    name = humanize_module(short_name(workflow.module))
    states = workflow.status_values

    if length(states) < 2 do
      nil
    else
      state_explanations =
        states
        |> Enum.map(fn s -> "- **#{humanize_state(s)}**: #{explain_state(s)}" end)
        |> Enum.join("\n")

      diagram = MermaidGenerator.workflow_diagram(workflow)

      transitions_text =
        if workflow.transitions != [] do
          trans =
            workflow.transitions
            |> Enum.take(5)
            |> Enum.map(fn t -> "- #{humanize_transition(t.function)}" end)
            |> Enum.join("\n")

          "\n\n**How items move between states:**\n\n#{trans}"
        else
          ""
        end

      """
      ### #{name} Workflow

      Items of type **#{name}** move through these stages:

      #{state_explanations}

      #{if diagram != "", do: "**Visual diagram:**\n\n#{diagram}", else: ""}#{transitions_text}
      """
      |> String.trim()
    end
  end

  defp format_data_concept(schema) do
    name = humanize_module(short_name(schema.module))

    fields =
      schema.fields
      |> Enum.reject(fn f -> f.name in [:id, :inserted_at, :updated_at] end)
      |> Enum.take(8)
      |> Enum.map(fn f -> "- **#{humanize_field(f.name)}** (#{humanize_type(f.type)})" end)
      |> Enum.join("\n")

    relationships =
      if schema.associations != [] do
        rels =
          schema.associations
          |> Enum.map(fn a ->
            "- #{relation_phrase(a.type)} #{humanize_module(to_string(a.target))}"
          end)
          |> Enum.join("\n")

        "\n\n**Relationships:**\n#{rels}"
      else
        ""
      end

    """
    ### #{name}

    #{describe_concept(name)}

    **Information tracked:**
    #{fields}#{relationships}
    """
    |> String.trim()
  end

  # ---------------------------------------------------------------------------
  # Extraction Helpers
  # ---------------------------------------------------------------------------

  defp extract_features(routes, live_views, _analysis) do
    # Group routes by controller to identify features
    controller_groups =
      routes
      |> Enum.group_by(& &1.controller)

    features_from_routes =
      controller_groups
      |> Enum.map(fn {controller, ctrl_routes} ->
        name = humanize_module(short_name(controller))
        actions = ctrl_routes |> Enum.map(& &1.action) |> Enum.uniq()

        %{
          name: name,
          description: describe_feature(name, actions),
          actions: Enum.map(actions, &humanize_action/1)
        }
      end)

    features_from_live_views =
      live_views
      |> Enum.filter(fn lv ->
        module = short_name(lv.module)
        not String.ends_with?(module, "Component")
      end)
      |> Enum.map(fn lv ->
        name = humanize_module(short_name(lv.module))
        events = Map.get(lv, :events, [])

        %{
          name: name,
          description: "Interactive #{String.downcase(name)} with real-time updates.",
          actions: Enum.map(events, &humanize_event/1)
        }
      end)

    (features_from_routes ++ features_from_live_views)
    |> Enum.uniq_by(& &1.name)
  end

  defp group_routes_by_area(routes, scopes) do
    scope_prefixes = Enum.map(scopes, & &1.path) |> Enum.reject(&(&1 == "/"))

    routes
    |> Enum.group_by(fn route ->
      matching_scope =
        scope_prefixes
        |> Enum.find(fn prefix -> String.starts_with?(route.path, prefix) end)

      matching_scope || "/"
    end)
  end

  defp extract_glossary_terms(analysis) do
    # Extract terms from schemas, workflows, and routes
    schema_terms =
      analysis.schemas
      |> Enum.map(fn s ->
        name = short_name(s.module)
        %{term: humanize_module(name), definition: describe_concept(humanize_module(name))}
      end)

    workflow_terms =
      analysis.workflows
      |> Enum.flat_map(fn w ->
        w.status_values
        |> Enum.map(fn state ->
          %{term: humanize_state(state), definition: explain_state(state)}
        end)
      end)

    (schema_terms ++ workflow_terms)
    |> Enum.uniq_by(& &1.term)
    |> Enum.take(20)
  end

  defp gather_stats(analysis) do
    %{
      pages: length(analysis.live_view.live_views),
      routes: length(analysis.routes.routes),
      data_types: length(analysis.schemas),
      workflows: length(Enum.filter(analysis.workflows, fn w -> length(w.status_values) >= 2 end)),
      components: length(analysis.live_view.live_components) + length(analysis.live_view.function_components)
    }
  end

  defp stats_list(stats) do
    [
      if(stats.pages > 0, do: "- **#{stats.pages}** interactive pages"),
      if(stats.routes > 0, do: "- **#{stats.routes}** available endpoints"),
      if(stats.data_types > 0, do: "- **#{stats.data_types}** types of data"),
      if(stats.workflows > 0, do: "- **#{stats.workflows}** workflows with tracked states"),
      if(stats.components > 0, do: "- **#{stats.components}** reusable UI components")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Humanization Helpers
  # ---------------------------------------------------------------------------

  defp format_project_name(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp project_name(analysis) do
    format_project_name(analysis.config.project_name)
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

  defp humanize_action(action) do
    case to_string(action) do
      "index" -> "View list"
      "show" -> "View details"
      "new" -> "Create new"
      "create" -> "Save new"
      "edit" -> "Edit existing"
      "update" -> "Save changes"
      "delete" -> "Remove"
      other -> String.capitalize(String.replace(other, "_", " "))
    end
  end

  defp humanize_event(event) do
    event
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.capitalize()
  end

  defp humanize_state(state) do
    state
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_field(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_type(type) do
    case type do
      :string -> "text"
      :text -> "text"
      :integer -> "number"
      :float -> "decimal"
      :decimal -> "decimal"
      :boolean -> "yes/no"
      :date -> "date"
      :time -> "time"
      :datetime -> "date and time"
      :utc_datetime -> "date and time"
      :utc_datetime_usec -> "date and time"
      :naive_datetime -> "date and time"
      :naive_datetime_usec -> "date and time"
      :binary -> "file data"
      :map -> "structured data"
      {:array, inner} -> "list of #{humanize_type(inner)}"
      {:parameterized, Ecto.Enum, _} -> "choice"
      other -> to_string(other)
    end
  end

  defp humanize_area("/"), do: "Main"
  defp humanize_area(area) do
    area
    |> String.trim_leading("/")
    |> String.split("/")
    |> List.first()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_transition(function) do
    function
    |> String.replace(~r/^def\s+/, "")
    |> String.replace(~r/\(.*$/, "")
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp relation_phrase(:has_many), do: "Has multiple"
  defp relation_phrase(:has_one), do: "Has one"
  defp relation_phrase(:belongs_to), do: "Belongs to a"
  defp relation_phrase(:many_to_many), do: "Connected to multiple"
  defp relation_phrase(_), do: "Related to"

  defp explain_state(state) do
    state_str = to_string(state) |> String.downcase()

    cond do
      state_str in ~w(pending waiting queued) -> "Waiting to be processed"
      state_str in ~w(active enabled running processing in_progress) -> "Currently being worked on"
      state_str in ~w(completed done finished resolved closed) -> "Successfully finished"
      state_str in ~w(cancelled canceled cancelled_by_user) -> "Stopped by user request"
      state_str in ~w(failed error errored) -> "Something went wrong"
      state_str in ~w(draft) -> "Not yet submitted"
      state_str in ~w(submitted) -> "Sent for review"
      state_str in ~w(approved) -> "Accepted and confirmed"
      state_str in ~w(rejected denied) -> "Not accepted"
      state_str in ~w(archived) -> "Stored for historical reference"
      state_str in ~w(suspended paused on_hold) -> "Temporarily stopped"
      state_str in ~w(scheduled) -> "Planned for future processing"
      state_str in ~w(triggered fired) -> "Event has occurred"
      state_str in ~w(acknowledged acked) -> "Someone has seen it"
      true -> "Item is in the #{humanize_state(state)} state"
    end
  end

  defp describe_feature(name, actions) do
    name_lower = String.downcase(name)
    has_crud = Enum.any?(actions, &(&1 in ~w(index show new create edit update delete)a))

    cond do
      has_crud -> "Manage #{name_lower} records — view, create, edit, and delete."
      String.contains?(name_lower, "dashboard") -> "Overview page showing key metrics and status."
      String.contains?(name_lower, "report") -> "Generate and view reports."
      String.contains?(name_lower, "setting") -> "Configure application preferences."
      String.contains?(name_lower, "auth") -> "Handle user authentication and access."
      String.contains?(name_lower, "session") -> "Manage user sessions."
      true -> "#{name} functionality."
    end
  end

  defp describe_concept(name) do
    name_lower = String.downcase(name)

    cond do
      String.contains?(name_lower, "user") -> "Represents a person who uses the system."
      String.contains?(name_lower, "account") -> "Stores account information."
      String.contains?(name_lower, "organization") or String.contains?(name_lower, "organisation") ->
        "A company or team that uses the system."
      String.contains?(name_lower, "team") -> "A group of users working together."
      String.contains?(name_lower, "incident") -> "An event or issue that needs attention."
      String.contains?(name_lower, "alert") -> "A notification about something important."
      String.contains?(name_lower, "schedule") -> "Defines when things happen."
      String.contains?(name_lower, "shift") -> "A time period when someone is on duty."
      String.contains?(name_lower, "notification") -> "A message sent to users."
      String.contains?(name_lower, "message") -> "Communication between users or the system."
      String.contains?(name_lower, "event") -> "Something that happened in the system."
      String.contains?(name_lower, "log") -> "A record of activity."
      String.contains?(name_lower, "setting") -> "Configuration options."
      String.contains?(name_lower, "token") -> "A secure key for authentication."
      String.contains?(name_lower, "session") -> "An active user connection."
      String.contains?(name_lower, "invite") or String.contains?(name_lower, "invitation") ->
        "An invitation to join the system."
      String.contains?(name_lower, "role") -> "Defines what a user can do."
      String.contains?(name_lower, "permission") -> "Access rights to features."
      String.contains?(name_lower, "task") -> "Work that needs to be done."
      String.contains?(name_lower, "project") -> "A collection of related work."
      String.contains?(name_lower, "comment") -> "Notes or feedback on something."
      String.contains?(name_lower, "attachment") -> "A file linked to a record."
      String.contains?(name_lower, "tag") -> "A label for organizing items."
      String.contains?(name_lower, "category") -> "A way to group related items."
      true -> "Stores #{name_lower} information."
    end
  end
end
