defmodule ElixirCartographer.Miners.TestMiner do
  @moduledoc """
  Mines test files for test inventory, edge cases, and coverage gaps.
  """

  @doc """
  Return empty test data when test mining is skipped.
  """
  def empty do
    %{
      total_tests: 0,
      test_files: [],
      edge_cases: [],
      coverage_gaps: [],
      describe_blocks: []
    }
  end

  @doc """
  Analyze test files in the project.
  """
  def analyze(config) do
    test_path = config.test_path
    lib_path = config.lib_path

    if File.dir?(test_path) do
      test_files = discover_test_files(test_path)
      parsed_tests = parse_test_files(test_files)
      edge_cases = extract_edge_cases(parsed_tests)
      coverage_gaps = find_coverage_gaps(lib_path, test_path)

      total_tests = Enum.reduce(parsed_tests, 0, fn tf, acc -> acc + length(tf.tests) end)

      %{
        total_tests: total_tests,
        test_files: parsed_tests,
        edge_cases: edge_cases,
        coverage_gaps: coverage_gaps,
        describe_blocks: Enum.flat_map(parsed_tests, & &1.describes)
      }
    else
      empty()
    end
  end

  defp discover_test_files(test_path) do
    Path.wildcard(Path.join(test_path, "**/*_test.exs"))
  end

  defp parse_test_files(files) do
    Enum.map(files, fn path ->
      content = File.read!(path)
      tests = extract_tests(content)
      describes = extract_describes(content)
      module = extract_test_module(content)

      %{
        path: path,
        module: module,
        tests: tests,
        describes: describes,
        test_count: length(tests)
      }
    end)
  end

  defp extract_tests(content) do
    # Match test "description" and test "description", %{} patterns
    pattern = ~r/test\s+"([^"]+)"/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, description] ->
      %{
        description: description,
        type: classify_test(description)
      }
    end)
  end

  defp extract_describes(content) do
    pattern = ~r/describe\s+"([^"]+)"/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, description] ->
      %{description: description}
    end)
  end

  defp extract_test_module(content) do
    case Regex.run(~r/defmodule\s+([\w.]+)/, content) do
      [_, module] -> module
      _ -> nil
    end
  end

  defp classify_test(description) do
    desc_lower = String.downcase(description)

    cond do
      Regex.match?(~r/error|fail|invalid|reject|bad|wrong|nil|empty|missing/, desc_lower) ->
        :error_case

      Regex.match?(~r/edge|boundary|limit|max|min|overflow|zero|negative/, desc_lower) ->
        :edge_case

      Regex.match?(~r/when|if|given|with|without/, desc_lower) ->
        :conditional

      Regex.match?(~r/should not|doesn't|cannot|must not|prevents/, desc_lower) ->
        :negative

      true ->
        :happy_path
    end
  end

  @doc """
  Extract descriptions that sound like edge cases.
  """
  def extract_edge_cases(parsed_tests) do
    parsed_tests
    |> Enum.flat_map(fn tf ->
      tf.tests
      |> Enum.filter(fn t -> t.type in [:edge_case, :error_case] end)
      |> Enum.map(fn t ->
        %{
          description: t.description,
          type: t.type,
          test_file: tf.path,
          module: tf.module
        }
      end)
    end)
  end

  @doc """
  Find modules in lib/ that don't have corresponding test files.
  """
  def find_coverage_gaps(lib_path, test_path) do
    lib_modules = discover_lib_modules(lib_path)
    test_modules = discover_test_modules(test_path)

    # Normalize test module names for matching
    tested_patterns =
      test_modules
      |> Enum.map(fn path ->
        path
        |> Path.basename(".exs")
        |> String.replace("_test", "")
      end)

    lib_modules
    |> Enum.filter(fn {_path, basename} ->
      not Enum.any?(tested_patterns, fn test_name ->
        basename == test_name
      end)
    end)
    |> Enum.map(fn {path, _basename} ->
      %{file: path, has_test: false}
    end)
  end

  defp discover_lib_modules(lib_path) do
    if File.dir?(lib_path) do
      Path.wildcard(Path.join(lib_path, "**/*.ex"))
      |> Enum.map(fn path ->
        basename = Path.basename(path, ".ex")
        {path, basename}
      end)
    else
      []
    end
  end

  defp discover_test_modules(test_path) do
    if File.dir?(test_path) do
      Path.wildcard(Path.join(test_path, "**/*_test.exs"))
    else
      []
    end
  end
end
