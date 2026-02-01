defmodule ElixirCartographer.Progress do
  @moduledoc """
  Progress reporting for cartography pipeline.
  """

  def start(label) do
    IO.puts("#{IO.ANSI.cyan()}▸ #{label}#{IO.ANSI.reset()}")
    System.monotonic_time(:millisecond)
  end

  def done(start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Done in #{format_time(elapsed)}")
  end

  def info(msg) do
    IO.puts("  #{IO.ANSI.light_black()}#{msg}#{IO.ANSI.reset()}")
  end

  def section(label) do
    IO.puts("\n#{IO.ANSI.bright()}#{IO.ANSI.yellow()}═══ #{label} ═══#{IO.ANSI.reset()}")
  end

  def warn(msg) do
    IO.puts("  #{IO.ANSI.yellow()}⚠ #{msg}#{IO.ANSI.reset()}")
  end

  def error(msg) do
    IO.puts("  #{IO.ANSI.red()}✗ #{msg}#{IO.ANSI.reset()}")
  end

  defp format_time(ms) when ms < 1000, do: "#{ms}ms"
  defp format_time(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
