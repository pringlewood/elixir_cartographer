defmodule ElixirCartographer.Config do
  @moduledoc """
  Configuration for a cartography run.
  """

  defstruct [
    :project_path,
    :output_path,
    :project_name,
    :lib_path,
    :test_path,
    :config_path,
    :mix_exs_path,
    skip_git: false,
    skip_tests: false,
    verbose: false,
    compact: false
  ]

  @doc """
  Create a new config from a project path and options.
  """
  def new(project_path, opts \\ []) do
    project_path = Path.expand(project_path)
    output_path = Keyword.get(opts, :output, Path.join(project_path, "cartographer_docs"))

    project_name =
      Keyword.get_lazy(opts, :name, fn ->
        detect_project_name(project_path)
      end)

    %__MODULE__{
      project_path: project_path,
      output_path: Path.expand(output_path),
      project_name: project_name,
      lib_path: Path.join(project_path, "lib"),
      test_path: Path.join(project_path, "test"),
      config_path: Path.join(project_path, "config"),
      mix_exs_path: Path.join(project_path, "mix.exs"),
      skip_git: Keyword.get(opts, :skip_git, false),
      skip_tests: Keyword.get(opts, :skip_tests, false),
      verbose: Keyword.get(opts, :verbose, false),
      compact: Keyword.get(opts, :compact, false)
    }
  end

  defp detect_project_name(project_path) do
    mix_exs = Path.join(project_path, "mix.exs")

    if File.exists?(mix_exs) do
      case File.read(mix_exs) do
        {:ok, content} ->
          case Regex.run(~r/app:\s*:(\w+)/, content) do
            [_, name] -> name
            _ -> Path.basename(project_path)
          end

        _ ->
          Path.basename(project_path)
      end
    else
      Path.basename(project_path)
    end
  end
end
