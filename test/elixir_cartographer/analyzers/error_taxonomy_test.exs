defmodule ElixirCartographer.Analyzers.ErrorTaxonomyTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.ErrorTaxonomy

  describe "analyze/1" do
    test "detects rescue patterns" do
      content = """
      defmodule MyApp.Worker do
        def run do
          try do
            do_work()
          rescue
            e in [RuntimeError, ArgumentError] ->
              {:error, e}
          end
        end
      end
      """
      {:ok, ast} = Code.string_to_quoted(content)
      parsed = %{"worker.ex" => %{ast: ast, content: content}}

      errors = ErrorTaxonomy.analyze(parsed)
      rescue_errors = Enum.filter(errors, &(&1.type == :rescue))
      assert length(rescue_errors) >= 1
    end

    test "detects error return patterns" do
      content = """
      defmodule MyApp.Service do
        def fetch(id) do
          case Repo.get(User, id) do
            nil -> {:error, :not_found}
            user -> {:ok, user}
          end
        end

        def validate(data) do
          if valid?(data), do: :ok, else: {:error, :invalid_data}
        end
      end
      """
      {:ok, ast} = Code.string_to_quoted(content)
      parsed = %{"service.ex" => %{ast: ast, content: content}}

      errors = ErrorTaxonomy.analyze(parsed)
      error_returns = Enum.filter(errors, &(&1.type == :error_return))
      reasons = Enum.map(error_returns, & &1.reason)

      assert "not_found" in reasons
      assert "invalid_data" in reasons
    end

    test "handles files with no error patterns" do
      content = """
      defmodule MyApp.Simple do
        def hello, do: :world
      end
      """
      {:ok, ast} = Code.string_to_quoted(content)
      parsed = %{"simple.ex" => %{ast: ast, content: content}}

      errors = ErrorTaxonomy.analyze(parsed)
      assert errors == []
    end

    test "handles nil ASTs" do
      parsed = %{"bad.ex" => %{ast: nil, content: ""}}
      errors = ErrorTaxonomy.analyze(parsed)
      assert errors == []
    end
  end
end
