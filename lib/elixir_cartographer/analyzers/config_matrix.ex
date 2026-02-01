defmodule ElixirCartographer.Analyzers.ConfigMatrix do
  @moduledoc """
  Extracts all configuration: env vars, app configs, runtime config, feature flags.
  """

  @doc """
  Analyze config files and source code for configuration patterns.
  """
  def analyze(config) do
    config_files = discover_config_files(config.config_path)
    source_env_vars = scan_source_for_env_vars(config.lib_path)
    config_env_vars = scan_configs_for_env_vars(config_files)
    app_configs = extract_app_configs(config_files)
    runtime_configs = extract_runtime_configs(config_files)

    all_env_vars =
      (source_env_vars ++ config_env_vars)
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    %{
      env_vars: all_env_vars,
      app_configs: app_configs,
      runtime_configs: runtime_configs,
      config_files: Enum.map(config_files, &elem(&1, 0))
    }
  end

  defp discover_config_files(config_path) do
    if File.dir?(config_path) do
      Path.wildcard(Path.join(config_path, "*.exs"))
      |> Enum.map(fn path ->
        {path, File.read!(path)}
      end)
    else
      []
    end
  end

  defp scan_source_for_env_vars(lib_path) do
    if File.dir?(lib_path) do
      Path.wildcard(Path.join(lib_path, "**/*.ex"))
      |> Enum.flat_map(fn path ->
        content = File.read!(path)
        extract_env_var_refs(content, path)
      end)
    else
      []
    end
  end

  defp scan_configs_for_env_vars(config_files) do
    config_files
    |> Enum.flat_map(fn {path, content} ->
      extract_env_var_refs(content, path)
    end)
  end

  defp extract_env_var_refs(content, path) do
    # System.get_env("VAR") pattern
    system_pattern = ~r/System\.(?:get_env|fetch_env!?)\(\s*"([^"]+)"\s*(?:,\s*"?([^")\s]*)"?)?\)/

    Regex.scan(system_pattern, content)
    |> Enum.map(fn
      [_full, name] -> %{name: name, default: nil, source: Path.basename(path)}
      [_full, name, default] -> %{name: name, default: default, source: Path.basename(path)}
    end)
  end

  defp extract_app_configs(config_files) do
    config_files
    |> Enum.flat_map(fn {path, content} ->
      # config :app, Module, key: val pattern
      pattern = ~r/config\s+:(\w+)\s*,\s*([A-Z][\w.]*)/

      Regex.scan(pattern, content)
      |> Enum.map(fn [_full, app, module] ->
        %{app: app, module: module, source: Path.basename(path)}
      end)
    end)
    |> Enum.uniq_by(fn %{app: app, module: module} -> {app, module} end)
  end

  defp extract_runtime_configs(config_files) do
    runtime_file = Enum.find(config_files, fn {path, _} ->
      String.contains?(path, "runtime.exs")
    end)

    case runtime_file do
      nil -> []
      {path, content} ->
        # Extract all config blocks from runtime.exs
        pattern = ~r/config\s+:(\w+)\s*,?\s*(?::(\w+)|([A-Z][\w.]*))?/

        Regex.scan(pattern, content)
        |> Enum.map(fn
          [_full, app] -> %{app: app, key: nil, source: Path.basename(path)}
          [_full, app, key, ""] -> %{app: app, key: key, source: Path.basename(path)}
          [_full, app, "", module] -> %{app: app, key: module, source: Path.basename(path)}
          other -> %{app: inspect(other), key: nil, source: Path.basename(path)}
        end)
    end
  end
end
