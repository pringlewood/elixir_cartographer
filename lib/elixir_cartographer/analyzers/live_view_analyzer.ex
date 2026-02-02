defmodule ElixirCartographer.Analyzers.LiveViewAnalyzer do
  @moduledoc """
  Detects LiveView modules, LiveComponents, function components, event handlers,
  live navigation, assigns/streams, PubSub patterns, JS commands, uploads, and hooks.
  """

  import ElixirCartographer.AstUtils, only: [parts_to_string: 1]

  defstruct live_views: [],
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

  @doc """
  Analyze parsed files for LiveView patterns.
  """
  def analyze(parsed_files) do
    results =
      parsed_files
      |> Enum.flat_map(fn {path, %{ast: ast, content: content}} ->
        modules = if ast, do: extract_modules(ast, path, content), else: []
        content_patterns = extract_content_patterns(content, path)
        modules ++ content_patterns
      end)

    %__MODULE__{
      live_views: Enum.filter(results, &(&1.type == :live_view)),
      live_components: Enum.filter(results, &(&1.type == :live_component)),
      function_components: Enum.filter(results, &(&1.type == :function_component)),
      event_handlers: Enum.filter(results, &(&1.type == :event_handler)),
      live_navigation: Enum.filter(results, &(&1.type == :live_navigation)),
      assigns_usage: Enum.filter(results, &(&1.type == :assigns_usage)),
      streams_usage: Enum.filter(results, &(&1.type == :streams_usage)),
      pubsub_patterns: Enum.filter(results, &(&1.type == :pubsub)),
      js_commands: Enum.filter(results, &(&1.type == :js_command)),
      uploads: Enum.filter(results, &(&1.type == :upload)),
      hooks: Enum.filter(results, &(&1.type == :hook))
    }
  end

  # ---------------------------------------------------------------------------
  # AST-based extraction
  # ---------------------------------------------------------------------------

  defp extract_modules(ast, path, content) do
    {_, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [{:__aliases__, _, parts} | rest]} = node, acc ->
          module_name = parts_to_string(parts)
          uses = extract_uses(rest)

          entry =
            cond do
              "Phoenix.LiveView" in uses ->
                callbacks = extract_liveview_callbacks(rest)
                events = extract_event_names(content)
                nav = extract_navigation_calls(content)

                %{
                  type: :live_view,
                  module: module_name,
                  path: path,
                  callbacks: callbacks,
                  events: events,
                  navigation: nav
                }

              "Phoenix.LiveComponent" in uses ->
                callbacks = extract_component_callbacks(rest)
                events = extract_event_names(content)

                %{
                  type: :live_component,
                  module: module_name,
                  path: path,
                  callbacks: callbacks,
                  events: events
                }

              "Phoenix.Component" in uses ->
                attrs = extract_attrs(content)
                slots = extract_slots(content)

                %{
                  type: :function_component,
                  module: module_name,
                  path: path,
                  attrs: attrs,
                  slots: slots,
                  has_heex: String.contains?(content, "~H")
                }

              true ->
                nil
            end

          if entry do
            {node, [entry | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp extract_uses(ast) do
    {_, uses} =
      Macro.prewalk(ast, [], fn
        {:use, _meta, [{:__aliases__, _, parts} | _]} = node, acc ->
          {node, [parts_to_string(parts) | acc]}

        node, acc ->
          {node, acc}
      end)

    uses
  end

  @liveview_callbacks [:mount, :handle_event, :handle_info, :handle_params, :render, :terminate]
  @component_callbacks [:mount, :update, :render, :handle_event, :preload]

  defp extract_liveview_callbacks(ast) do
    {_, callbacks} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{name, _, _args} | _]} = node, acc when name in @liveview_callbacks ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    callbacks |> Enum.reverse() |> Enum.uniq()
  end

  defp extract_component_callbacks(ast) do
    {_, callbacks} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{name, _, _args} | _]} = node, acc when name in @component_callbacks ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    callbacks |> Enum.reverse() |> Enum.uniq()
  end

  # ---------------------------------------------------------------------------
  # Regex / content-based extraction
  # ---------------------------------------------------------------------------

  defp extract_content_patterns(content, path) do
    event_handlers = extract_event_handler_entries(content, path)
    navigation = extract_navigation_entries(content, path)
    assigns = extract_assigns_entries(content, path)
    streams = extract_streams_entries(content, path)
    pubsub = extract_pubsub_entries(content, path)
    js = extract_js_entries(content, path)
    uploads = extract_upload_entries(content, path)
    hooks = extract_hook_entries(content, path)

    event_handlers ++ navigation ++ assigns ++ streams ++ pubsub ++ js ++ uploads ++ hooks
  end

  defp extract_event_names(content) do
    ~r/handle_event\(\s*"([^"]+)"/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end

  defp extract_event_handler_entries(content, path) do
    ~r/def\s+handle_event\(\s*"([^"]+)"/
    |> Regex.scan(content)
    |> Enum.map(fn [_, event_name] ->
      %{type: :event_handler, event: event_name, path: path}
    end)
    |> Enum.uniq_by(& &1.event)
  end

  defp extract_navigation_calls(content) do
    nav_fns = ~w(push_navigate push_patch live_redirect live_patch)

    nav_fns
    |> Enum.filter(fn fn_name -> String.contains?(content, fn_name) end)
  end

  defp extract_navigation_entries(content, path) do
    nav_pattern = ~r/(push_navigate|push_patch|live_redirect|live_patch)\(/

    Regex.scan(nav_pattern, content)
    |> Enum.map(fn [_, fn_name] ->
      %{type: :live_navigation, function: fn_name, path: path}
    end)
    |> Enum.uniq_by(& &1.function)
  end

  defp extract_assigns_entries(content, path) do
    assign_pattern = ~r/(assign|assign_new)\(/

    matches = Regex.scan(assign_pattern, content)

    if matches != [] do
      fns =
        matches
        |> Enum.map(fn [_, fn_name] -> fn_name end)
        |> Enum.uniq()

      [%{type: :assigns_usage, functions: fns, path: path}]
    else
      []
    end
  end

  defp extract_streams_entries(content, path) do
    stream_pattern = ~r/(stream_insert|stream_delete|stream)\(/

    matches = Regex.scan(stream_pattern, content)

    if matches != [] do
      fns =
        matches
        |> Enum.map(fn [_, fn_name] -> fn_name end)
        |> Enum.uniq()

      [%{type: :streams_usage, functions: fns, path: path}]
    else
      []
    end
  end

  defp extract_pubsub_entries(content, path) do
    pubsub_pattern = ~r/Phoenix\.PubSub\.(subscribe|broadcast|broadcast!|broadcast_from|broadcast_from!)\(/

    matches = Regex.scan(pubsub_pattern, content)

    if matches != [] do
      fns =
        matches
        |> Enum.map(fn [_, fn_name] -> fn_name end)
        |> Enum.uniq()

      [%{type: :pubsub, functions: fns, path: path}]
    else
      []
    end
  end

  defp extract_js_entries(content, path) do
    js_pattern = ~r/JS\.(push|toggle|show|hide|add_class|remove_class|transition|dispatch|set_attribute|remove_attribute|focus|focus_first|navigate|patch)\(/

    matches = Regex.scan(js_pattern, content)

    if matches != [] do
      commands =
        matches
        |> Enum.map(fn [_, cmd] -> cmd end)
        |> Enum.uniq()

      [%{type: :js_command, commands: commands, path: path}]
    else
      []
    end
  end

  defp extract_upload_entries(content, path) do
    upload_pattern = ~r/(allow_upload|consume_uploaded_entries|consume_uploaded_entry|uploaded_entries)\(/

    matches = Regex.scan(upload_pattern, content)

    if matches != [] do
      fns =
        matches
        |> Enum.map(fn [_, fn_name] -> fn_name end)
        |> Enum.uniq()

      [%{type: :upload, functions: fns, path: path}]
    else
      []
    end
  end

  defp extract_hook_entries(content, path) do
    hook_pattern = ~r/phx-hook="([^"]+)"/

    matches = Regex.scan(hook_pattern, content)

    if matches != [] do
      hooks =
        matches
        |> Enum.map(fn [_, hook_name] -> hook_name end)
        |> Enum.uniq()

      Enum.map(hooks, fn hook ->
        %{type: :hook, hook: hook, path: path}
      end)
    else
      []
    end
  end

  defp extract_attrs(content) do
    ~r/attr\s+:(\w+)\s*,\s*:?(\w+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name, type] -> %{name: name, type: type} end)
  end

  defp extract_slots(content) do
    ~r/slot\s+:(\w+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_, name] -> name end)
    |> Enum.uniq()
  end
end
