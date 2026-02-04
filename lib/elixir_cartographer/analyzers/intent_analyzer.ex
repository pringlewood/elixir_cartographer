defmodule ElixirCartographer.Analyzers.IntentAnalyzer do
  @moduledoc """
  Analyzes code to infer user-facing intent and meaning.
  
  Reads function names, implementations, and patterns to understand
  what the code DOES from a user's perspective.
  """

  @doc """
  Analyze parsed files to extract user-facing intents.
  """
  def analyze(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{content: content}} ->
      extract_intents(content, path)
    end)
    |> group_by_context()
  end

  defp extract_intents(content, path) do
    intents = []

    # Extract function-level intents
    intents = intents ++ extract_function_intents(content, path)

    # Extract notification patterns (what triggers notifications)
    intents = intents ++ extract_notification_intents(content, path)

    # Extract workflow actions (state transitions)
    intents = intents ++ extract_workflow_intents(content, path)

    intents
  end

  # ---------------------------------------------------------------------------
  # Function Intent Extraction
  # ---------------------------------------------------------------------------

  defp extract_function_intents(content, path) do
    # Match public function definitions and analyze their names + bodies
    pattern = ~r/def\s+(\w+)\(([^)]*)\)[^d]*?do([\s\S]*?)(?=\n\s*def\s|\n\s*defp\s|\nend\n|\z)/

    Regex.scan(pattern, content)
    |> Enum.flat_map(fn [_, func_name, args, body] ->
      intent = infer_intent_from_function(func_name, args, body)
      if intent do
        [%{
          type: :action,
          name: func_name,
          intent: intent,
          context: extract_context(path),
          path: path
        }]
      else
        []
      end
    end)
  end

  defp infer_intent_from_function(name, args, body) do
    name_str = to_string(name)
    
    cond do
      # CRUD operations
      String.starts_with?(name_str, "create_") ->
        resource = String.replace(name_str, "create_", "")
        side_effects = extract_side_effects(body)
        build_create_intent(resource, side_effects)

      String.starts_with?(name_str, "update_") ->
        resource = String.replace(name_str, "update_", "")
        "Update #{humanize(resource)} information"

      String.starts_with?(name_str, "delete_") || String.starts_with?(name_str, "remove_") ->
        resource = String.replace(name_str, ~r/^(delete_|remove_)/, "")
        "Remove a #{humanize(resource)}"

      String.starts_with?(name_str, "list_") ->
        resource = String.replace(name_str, "list_", "")
        filters = extract_filters(body)
        build_list_intent(resource, filters)

      String.starts_with?(name_str, "get_") ->
        resource = String.replace(name_str, ~r/^get_|!$/, "")
        "View #{humanize(resource)} details"

      # State transitions
      String.starts_with?(name_str, "acknowledge_") ->
        resource = humanize(String.replace(name_str, "acknowledge_", ""))
        "Acknowledge #{article(resource)} #{resource} to confirm you're handling it"

      String.starts_with?(name_str, "resolve_") ->
        resource = humanize(String.replace(name_str, "resolve_", ""))
        "Mark #{article(resource)} #{resource} as resolved when it's fixed"

      String.starts_with?(name_str, "escalate_") ->
        resource = humanize(String.replace(name_str, "escalate_", ""))
        "Escalate #{article(resource)} #{resource} to notify the next person"

      String.starts_with?(name_str, "cancel_") ->
        resource = humanize(String.replace(name_str, "cancel_", ""))
        "Cancel #{article(resource)} #{resource}"

      String.starts_with?(name_str, "approve_") ->
        resource = humanize(String.replace(name_str, "approve_", ""))
        "Approve #{article(resource)} #{resource}"

      String.starts_with?(name_str, "reject_") ->
        resource = humanize(String.replace(name_str, "reject_", ""))
        "Reject #{article(resource)} #{resource}"

      # Query operations
      String.starts_with?(name_str, "search_") ->
        resource = String.replace(name_str, "search_", "")
        "Search for #{humanize(resource)}s"

      String.starts_with?(name_str, "filter_") ->
        resource = String.replace(name_str, "filter_", "")
        "Filter #{humanize(resource)}s"

      # Add operations
      String.starts_with?(name_str, "add_") ->
        what = String.replace(name_str, "add_", "")
        "Add a #{humanize(what)}"

      # Send operations
      String.starts_with?(name_str, "send_") ->
        what = String.replace(name_str, "send_", "")
        "Send #{humanize(what)}"

      # Invite operations
      String.starts_with?(name_str, "invite_") ->
        what = String.replace(name_str, "invite_", "")
        "Invite #{humanize(what)}"

      # Check if it's a common action verb
      true ->
        infer_from_body(name_str, body)
    end
  end

  defp build_create_intent(resource, side_effects) do
    base = "Create a new #{humanize(resource)}"
    
    effects = []
    effects = if :notify in side_effects, do: effects ++ ["notifications are sent"], else: effects
    effects = if :slack in side_effects, do: effects ++ ["team is notified on Slack"], else: effects
    effects = if :email in side_effects, do: effects ++ ["email is sent"], else: effects
    effects = if :broadcast in side_effects, do: effects ++ ["updates appear in real-time"], else: effects

    if effects == [] do
      base
    else
      "#{base}. When created, #{Enum.join(effects, " and ")}"
    end
  end

  defp build_list_intent(resource, filters) do
    resource_name = humanize(resource)
    # Don't add 's' if already plural
    plural = if String.ends_with?(resource_name, "s"), do: resource_name, else: resource_name <> "s"
    base = "View all #{plural}"
    
    if filters == [] do
      base
    else
      filter_text = filters |> Enum.map(&humanize/1) |> Enum.join(", ")
      "#{base}. Can filter by #{filter_text}"
    end
  end

  defp extract_side_effects(body) do
    effects = []
    
    effects = if String.contains?(body, "notify") || String.contains?(body, "Notification"), 
               do: [:notify | effects], else: effects
    effects = if String.contains?(body, "Slack") || String.contains?(body, "slack"),
               do: [:slack | effects], else: effects
    effects = if String.contains?(body, "email") || String.contains?(body, "Email"),
               do: [:email | effects], else: effects
    effects = if String.contains?(body, "broadcast"),
               do: [:broadcast | effects], else: effects
    effects = if String.contains?(body, "sms") || String.contains?(body, "SMS"),
               do: [:sms | effects], else: effects
               
    effects
  end

  defp extract_filters(body) do
    filters = []
    
    # Look for filter patterns like `case Map.get(opts, :status)`
    filter_pattern = ~r/Map\.get\(\w+,\s*:(\w+)\)/
    
    Regex.scan(filter_pattern, body)
    |> Enum.map(fn [_, filter] -> filter end)
    |> Enum.uniq()
  end

  defp infer_from_body(name, body) do
    cond do
      String.contains?(body, "Repo.insert") -> "Create #{humanize(name)}"
      String.contains?(body, "Repo.update") -> "Update #{humanize(name)}"
      String.contains?(body, "Repo.delete") -> "Remove #{humanize(name)}"
      String.contains?(body, "Repo.all") -> "List #{humanize(name)}"
      true -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Notification Intent Extraction
  # ---------------------------------------------------------------------------

  defp extract_notification_intents(content, path) do
    patterns = [
      {~r/notify_(\w+)/, "Notifies about"},
      {~r/send_(\w+)_notification/, "Sends notification for"},
      {~r/broadcast_(\w+)/, "Updates in real-time when"}
    ]

    patterns
    |> Enum.flat_map(fn {pattern, prefix} ->
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, what] ->
        %{
          type: :notification,
          intent: "#{prefix} #{humanize(what)}",
          context: extract_context(path),
          path: path
        }
      end)
    end)
    |> Enum.uniq_by(& &1.intent)
  end

  # ---------------------------------------------------------------------------
  # Workflow Intent Extraction  
  # ---------------------------------------------------------------------------

  defp extract_workflow_intents(content, path) do
    # Look for state machine patterns
    # case status do "triggered" -> ... "acknowledged" -> ...
    pattern = ~r/case\s+\w+\.(\w+)\s+do\s+"(\w+)"\s*->/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, field, from_state] ->
      %{
        type: :workflow,
        field: field,
        state: from_state,
        intent: "When #{humanize(field)} is '#{humanize(from_state)}', actions can be taken",
        context: extract_context(path),
        path: path
      }
    end)
    |> Enum.uniq_by(fn w -> {w.field, w.state} end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_context(path) do
    path
    |> Path.basename(".ex")
    |> Macro.camelize()
  end

  defp humanize(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.downcase()
  end

  defp article(word) do
    if String.match?(word, ~r/^[aeiou]/i), do: "an", else: "a"
  end

  defp group_by_context(intents) do
    intents
    |> Enum.group_by(& &1.context)
    |> Enum.map(fn {context, items} ->
      %{
        context: context,
        actions: Enum.filter(items, & &1.type == :action),
        notifications: Enum.filter(items, & &1.type == :notification),
        workflows: Enum.filter(items, & &1.type == :workflow)
      }
    end)
  end
end
