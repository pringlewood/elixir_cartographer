defmodule ElixirCartographer.Analyzers.LiveViewAnalyzerTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.LiveViewAnalyzer

  @fixture_path Path.expand("../../fixtures/sample_live_view.ex", __DIR__)

  setup do
    content = File.read!(@fixture_path)
    {:ok, ast} = Code.string_to_quoted(content, file: @fixture_path)
    parsed = %{@fixture_path => %{ast: ast, content: content}}
    {:ok, parsed: parsed, content: content}
  end

  describe "analyze/1 — LiveView modules" do
    test "detects LiveView modules", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.live_views) >= 1

      lv = Enum.find(result.live_views, &(&1.module == "SampleApp.DashboardLive"))
      assert lv != nil
      assert lv.type == :live_view
    end

    test "extracts LiveView callbacks", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      lv = Enum.find(result.live_views, &(&1.module == "SampleApp.DashboardLive"))

      assert :mount in lv.callbacks
      assert :handle_event in lv.callbacks
      assert :handle_info in lv.callbacks
      assert :handle_params in lv.callbacks
      assert :render in lv.callbacks
    end

    test "extracts event names from LiveView", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      lv = Enum.find(result.live_views, &(&1.module == "SampleApp.DashboardLive"))

      assert "increment" in lv.events
      assert "save" in lv.events
      assert "delete" in lv.events
      assert "validate" in lv.events
    end

    test "extracts navigation calls from LiveView", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      lv = Enum.find(result.live_views, &(&1.module == "SampleApp.DashboardLive"))

      assert "push_navigate" in lv.navigation
    end

    test "detects multiple LiveView modules", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)

      modules = Enum.map(result.live_views, & &1.module)
      assert "SampleApp.DashboardLive" in modules
      assert "SampleApp.UploadLive" in modules
      assert "SampleApp.RealtimeLive" in modules
    end
  end

  describe "analyze/1 — LiveComponent modules" do
    test "detects LiveComponent modules", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.live_components) >= 1

      lc = Enum.find(result.live_components, &(&1.module == "SampleApp.FormComponent"))
      assert lc != nil
      assert lc.type == :live_component
    end

    test "extracts LiveComponent callbacks", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      lc = Enum.find(result.live_components, &(&1.module == "SampleApp.FormComponent"))

      assert :update in lc.callbacks
      assert :render in lc.callbacks
      assert :handle_event in lc.callbacks
    end

    test "extracts LiveComponent event names", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      lc = Enum.find(result.live_components, &(&1.module == "SampleApp.FormComponent"))

      assert "submit" in lc.events
    end
  end

  describe "analyze/1 — function components" do
    test "detects function component modules", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.function_components) >= 1

      fc = Enum.find(result.function_components, &(&1.module == "SampleApp.Components"))
      assert fc != nil
      assert fc.type == :function_component
    end

    test "extracts attr declarations", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      fc = Enum.find(result.function_components, &(&1.module == "SampleApp.Components"))

      attr_names = Enum.map(fc.attrs, & &1.name)
      assert "label" in attr_names
      assert "type" in attr_names
      assert "class" in attr_names
      assert "title" in attr_names
      assert "subtitle" in attr_names
    end

    test "extracts slot declarations", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      fc = Enum.find(result.function_components, &(&1.module == "SampleApp.Components"))

      assert "inner_block" in fc.slots
      assert "icon" in fc.slots
      assert "actions" in fc.slots
    end

    test "detects HEEx sigil usage", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      fc = Enum.find(result.function_components, &(&1.module == "SampleApp.Components"))

      assert fc.has_heex == true
    end
  end

  describe "analyze/1 — event handlers" do
    test "extracts all event handler entries", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)

      event_names = Enum.map(result.event_handlers, & &1.event)
      assert "increment" in event_names
      assert "save" in event_names
      assert "delete" in event_names
      assert "validate" in event_names
      assert "submit" in event_names
      assert "save_upload" in event_names
      assert "cancel_upload" in event_names
      assert "dismiss" in event_names
    end

    test "event handlers include path", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)

      Enum.each(result.event_handlers, fn eh ->
        assert eh.path == @fixture_path
      end)
    end
  end

  describe "analyze/1 — live navigation" do
    test "detects navigation function calls", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)

      nav_fns = Enum.map(result.live_navigation, & &1.function)
      assert "push_navigate" in nav_fns
      assert "push_patch" in nav_fns
    end
  end

  describe "analyze/1 — assigns & streams" do
    test "detects assign usage", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.assigns_usage) >= 1

      all_fns = Enum.flat_map(result.assigns_usage, & &1.functions)
      assert "assign" in all_fns
      assert "assign_new" in all_fns
    end

    test "detects stream usage", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.streams_usage) >= 1

      all_fns = Enum.flat_map(result.streams_usage, & &1.functions)
      assert "stream" in all_fns
      assert "stream_insert" in all_fns
      assert "stream_delete" in all_fns
    end
  end

  describe "analyze/1 — PubSub patterns" do
    test "detects PubSub subscribe and broadcast", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.pubsub_patterns) >= 1

      all_fns = Enum.flat_map(result.pubsub_patterns, & &1.functions)
      assert "subscribe" in all_fns
      assert "broadcast" in all_fns
    end
  end

  describe "analyze/1 — JS commands" do
    test "detects JS command usage", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.js_commands) >= 1

      all_cmds = Enum.flat_map(result.js_commands, & &1.commands)
      assert "push" in all_cmds
      assert "hide" in all_cmds
      assert "toggle" in all_cmds
    end
  end

  describe "analyze/1 — uploads" do
    test "detects upload handling", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.uploads) >= 1

      all_fns = Enum.flat_map(result.uploads, & &1.functions)
      assert "allow_upload" in all_fns
      assert "consume_uploaded_entries" in all_fns
    end
  end

  describe "analyze/1 — hooks" do
    test "detects phx-hook attributes", %{parsed: parsed} do
      result = LiveViewAnalyzer.analyze(parsed)
      assert length(result.hooks) >= 1

      hook_names = Enum.map(result.hooks, & &1.hook)
      assert "InfiniteScroll" in hook_names
      assert "RealtimeHook" in hook_names
    end
  end

  describe "analyze/1 — edge cases" do
    test "handles empty input" do
      result = LiveViewAnalyzer.analyze(%{})
      assert result.live_views == []
      assert result.live_components == []
      assert result.function_components == []
      assert result.event_handlers == []
    end

    test "handles files with no AST" do
      parsed = %{"bad.ex" => %{ast: nil, content: "not valid elixir {"}}
      result = LiveViewAnalyzer.analyze(parsed)
      assert result.live_views == []
    end

    test "handles files with no LiveView patterns" do
      content = """
      defmodule Plain do
        def hello, do: :world
      end
      """

      {:ok, ast} = Code.string_to_quoted(content)
      parsed = %{"plain.ex" => %{ast: ast, content: content}}
      result = LiveViewAnalyzer.analyze(parsed)

      assert result.live_views == []
      assert result.live_components == []
      assert result.function_components == []
    end
  end
end
