defmodule ElixirCartographer.CLI do
  @moduledoc """
  Escript entry point for Elixir Cartographer.
  """

  def main(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          name: :string,
          compact: :boolean,
          user_docs: :boolean,
          skip_git: :boolean,
          skip_tests: :boolean,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [
          o: :output,
          n: :name,
          c: :compact,
          u: :user_docs,
          v: :verbose,
          h: :help
        ]
      )

    if opts[:help] || args == [] do
      print_help()
    else
      project_path = List.first(args)
      ElixirCartographer.map(project_path, opts)
    end
  end

  defp print_help do
    IO.puts("""
    Elixir Cartographer v0.1.0

    Reverse-engineers an Elixir codebase into LLM-ready documentation.

    Usage:
      elixir_cartographer <project_path> [options]

    Options:
      -o, --output <path>    Output directory (default: <project>/cartographer_docs)
      -n, --name <name>      Project name (auto-detected from mix.exs)
      -c, --compact          Generate condensed output optimized for token efficiency
      -u, --user-docs        Generate USER_DOCS.md for non-technical audiences
                             (helpdesk, LLM training, onboarding)
      --skip-git             Skip git history analysis
      --skip-tests           Skip test file analysis
      -v, --verbose          Verbose output
      -h, --help             Show this help
    """)
  end
end
