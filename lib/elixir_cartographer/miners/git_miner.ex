defmodule ElixirCartographer.Miners.GitMiner do
  @moduledoc """
  Mines git history for commit classification, hotspots, and feature evolution.
  """

  @doc """
  Return empty git data when git mining is skipped.
  """
  def empty do
    %{
      total_commits: 0,
      hotspots: [],
      commit_types: %{},
      recent_activity: [],
      contributors: [],
      feature_timeline: []
    }
  end

  @doc """
  Analyze git history for the project.
  """
  def analyze(config) do
    project_path = config.project_path

    if File.dir?(Path.join(project_path, ".git")) do
      total_commits = count_commits(project_path)
      hotspots = find_hotspots(project_path)
      commit_types = classify_commits(project_path)
      recent_activity = recent_activity(project_path)
      contributors = top_contributors(project_path)
      feature_timeline = feature_timeline(project_path)

      %{
        total_commits: total_commits,
        hotspots: hotspots,
        commit_types: commit_types,
        recent_activity: recent_activity,
        contributors: contributors,
        feature_timeline: feature_timeline
      }
    else
      empty()
    end
  end

  defp count_commits(path) do
    case System.cmd("git", ["rev-list", "--count", "HEAD"], cd: path, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) |> String.to_integer()
      _ -> 0
    end
  end

  @doc """
  Find files with the most fix/bug commits (fragile code hotspots).
  """
  def find_hotspots(path) do
    # Get files changed in fix commits
    fix_pattern = ~r/fix|bug|hotfix|patch|repair|resolve/i

    case System.cmd("git", ["log", "--oneline", "--name-only", "--since=1 year ago", "--diff-filter=M"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> chunk_by_commits()
        |> Enum.filter(fn {msg, _files} -> Regex.match?(fix_pattern, msg) end)
        |> Enum.flat_map(fn {_msg, files} -> files end)
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> count end, :desc)
        |> Enum.take(20)
        |> Enum.map(fn {file, count} -> %{file: file, fix_count: count} end)

      _ ->
        []
    end
  end

  @doc """
  Classify commits by type (feature, bugfix, refactor, chore).
  """
  def classify_commits(path) do
    case System.cmd("git", ["log", "--oneline", "-500"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&classify_commit/1)
        |> Enum.frequencies()

      _ ->
        %{}
    end
  end

  defp classify_commit(line) do
    line_lower = String.downcase(line)

    cond do
      Regex.match?(~r/\bfix\b|bug|hotfix|patch/, line_lower) -> :bugfix
      Regex.match?(~r/\bfeat\b|add|implement|new|create/, line_lower) -> :feature
      Regex.match?(~r/refactor|clean|reorgani[zs]e|restructure/, line_lower) -> :refactor
      Regex.match?(~r/test|spec/, line_lower) -> :test
      Regex.match?(~r/doc|readme|comment/, line_lower) -> :docs
      Regex.match?(~r/deps?|upgrade|bump|update/, line_lower) -> :dependency
      Regex.match?(~r/ci|deploy|docker|config|infra/, line_lower) -> :infra
      Regex.match?(~r/style|format|lint|credo/, line_lower) -> :style
      Regex.match?(~r/merge|Merge/, line) -> :merge
      true -> :chore
    end
  end

  defp recent_activity(path) do
    case System.cmd("git", ["log", "--oneline", "--since=30 days ago", "--name-only"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.filter(&String.ends_with?(&1, ".ex"))
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> count end, :desc)
        |> Enum.take(20)
        |> Enum.map(fn {file, count} -> %{file: file, changes: count} end)

      _ ->
        []
    end
  end

  defp top_contributors(path) do
    case System.cmd("git", ["shortlog", "-sn", "--no-merges", "HEAD"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.take(10)
        |> Enum.map(fn line ->
          case Regex.run(~r/^\s*(\d+)\s+(.+)$/, line) do
            [_, count, name] -> %{name: String.trim(name), commits: String.to_integer(count)}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp feature_timeline(path) do
    # When were major directories first created?
    case System.cmd("git", ["log", "--diff-filter=A", "--name-only", "--format=%aI", "--", "lib/"], cd: path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> chunk_by_dates()
        |> Enum.flat_map(fn {date, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".ex"))
          |> Enum.map(fn file ->
            context = file |> String.split("/") |> Enum.take(3) |> Enum.join("/")
            {context, date}
          end)
        end)
        |> Enum.group_by(fn {context, _} -> context end, fn {_, date} -> date end)
        |> Enum.map(fn {context, dates} ->
          %{context: context, first_seen: Enum.min(dates), file_count: length(dates)}
        end)
        |> Enum.sort_by(& &1.first_seen)
        |> Enum.take(30)

      _ ->
        []
    end
  end

  defp chunk_by_commits(lines) do
    lines
    |> Enum.reduce({nil, [], []}, fn line, {current_msg, current_files, acc} ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          if current_msg do
            {nil, [], [{current_msg, current_files} | acc]}
          else
            {nil, [], acc}
          end

        # Commit line (hash + message)
        Regex.match?(~r/^[0-9a-f]{7,}/, trimmed) ->
          if current_msg do
            {trimmed, [], [{current_msg, current_files} | acc]}
          else
            {trimmed, [], acc}
          end

        # File path
        true ->
          {current_msg, [trimmed | current_files], acc}
      end
    end)
    |> then(fn {msg, files, acc} ->
      if msg, do: [{msg, files} | acc], else: acc
    end)
    |> Enum.reverse()
  end

  defp chunk_by_dates(lines) do
    lines
    |> Enum.reduce({nil, [], []}, fn line, {current_date, current_files, acc} ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          if current_date do
            {nil, [], [{current_date, current_files} | acc]}
          else
            {nil, [], acc}
          end

        Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, trimmed) ->
          date = String.slice(trimmed, 0, 10)
          if current_date do
            {date, [], [{current_date, current_files} | acc]}
          else
            {date, [], acc}
          end

        true ->
          {current_date, [trimmed | current_files], acc}
      end
    end)
    |> then(fn {date, files, acc} ->
      if date, do: [{date, files} | acc], else: acc
    end)
    |> Enum.reverse()
  end
end
