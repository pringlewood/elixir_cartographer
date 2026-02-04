defmodule ElixirCartographer.Analyzers.RolesAnalyzer do
  @moduledoc """
  Detects user roles, permissions, and authorization patterns in Phoenix applications.

  Extracts:
  - Role definitions from schemas and module attributes
  - Permission/policy modules (Bodyguard, custom policies)
  - Authorization plugs and checks
  - Role-based access patterns
  """

  @doc """
  Analyze parsed files for roles and permissions patterns.
  """
  def analyze(parsed_files) do
    roles = extract_roles(parsed_files)
    permissions = extract_permissions(parsed_files)
    policies = extract_policies(parsed_files)
    auth_plugs = extract_auth_plugs(parsed_files)

    %{
      roles: roles,
      permissions: permissions,
      policies: policies,
      auth_plugs: auth_plugs
    }
  end

  # ---------------------------------------------------------------------------
  # Role Extraction
  # ---------------------------------------------------------------------------

  defp extract_roles(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{content: content}} ->
      extract_roles_from_content(content, path)
    end)
    |> Enum.uniq_by(fn r -> {r.context, r.values} end)
  end

  defp extract_roles_from_content(content, path) do
    roles = []

    # Pattern 1: @roles module attribute
    roles = roles ++ extract_module_attr_roles(content, path)

    # Pattern 2: validate_inclusion(:role, [...])
    roles = roles ++ extract_validation_roles(content, path)

    # Pattern 3: Ecto.Enum for role field
    roles = roles ++ extract_enum_roles(content, path)

    # Pattern 4: Case/cond on role values
    roles = roles ++ extract_role_branches(content, path)

    roles
  end

  defp extract_module_attr_roles(content, path) do
    pattern = ~r/@roles\s+(\[[^\]]+\]|~w\([^)]+\)a?)/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, values_str] ->
      values = parse_values(values_str)
      %{
        source: :module_attribute,
        context: extract_context(path),
        path: path,
        values: values
      }
    end)
  end

  defp extract_validation_roles(content, path) do
    pattern = ~r/validate_inclusion\(\s*(?:\w+\s*,\s*)?:role\s*,\s*(\[[^\]]+\]|~w\([^)]+\)a?|@\w+)/

    Regex.scan(pattern, content)
    |> Enum.flat_map(fn
      [_, "@" <> attr_name] ->
        # Look up the attribute value
        attr_pattern = ~r/@#{attr_name}\s+(\[[^\]]+\]|~w\([^)]+\)a?)/
        case Regex.run(attr_pattern, content) do
          [_, values_str] ->
            [%{source: :validation, context: extract_context(path), path: path, values: parse_values(values_str)}]
          _ -> []
        end
      [_, values_str] ->
        [%{source: :validation, context: extract_context(path), path: path, values: parse_values(values_str)}]
    end)
  end

  defp extract_enum_roles(content, path) do
    pattern = ~r/field\s+:role\s*,\s*Ecto\.Enum\s*,\s*values:\s*(\[[^\]]+\]|~w\([^)]+\)a?)/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, values_str] ->
      %{
        source: :ecto_enum,
        context: extract_context(path),
        path: path,
        values: parse_values(values_str)
      }
    end)
  end

  defp extract_role_branches(content, path) do
    pattern = ~r/(?:case|cond|if|when)\s+.*\.role\s*(?:==|in|->)\s*[:\"](\w+)/

    matches = Regex.scan(pattern, content)

    if matches != [] do
      values = matches |> Enum.map(fn [_, v] -> v end) |> Enum.uniq()
      [%{source: :branch, context: extract_context(path), path: path, values: values}]
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Permission Extraction
  # ---------------------------------------------------------------------------

  defp extract_permissions(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{content: content}} ->
      extract_permissions_from_content(content, path)
    end)
    |> Enum.uniq_by(& &1.action)
  end

  defp extract_permissions_from_content(content, path) do
    permissions = []

    # Pattern 1: authorize/3 function definitions (Bodyguard style)
    permissions = permissions ++ extract_authorize_functions(content, path)

    # Pattern 2: can?/2 or authorized?/2 calls
    permissions = permissions ++ extract_can_calls(content, path)

    # Pattern 3: permit/3 definitions
    permissions = permissions ++ extract_permit_functions(content, path)

    permissions
  end

  defp extract_authorize_functions(content, path) do
    pattern = ~r/def\s+authorize\(\s*:(\w+)\s*,/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, action] ->
      %{
        type: :authorize,
        action: action,
        context: extract_context(path),
        path: path
      }
    end)
  end

  defp extract_can_calls(content, path) do
    pattern = ~r/(?:can\?|authorized\?|permit\?)\(\s*(?:\w+\s*,\s*)?:(\w+)/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, action] ->
      %{
        type: :check,
        action: action,
        context: extract_context(path),
        path: path
      }
    end)
  end

  defp extract_permit_functions(content, path) do
    pattern = ~r/def\s+permit\(\s*:(\w+)\s*,/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, action] ->
      %{
        type: :permit,
        action: action,
        context: extract_context(path),
        path: path
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Policy Module Extraction
  # ---------------------------------------------------------------------------

  defp extract_policies(parsed_files) do
    parsed_files
    |> Enum.filter(fn {path, _} ->
      String.contains?(path, "policy") || String.contains?(path, "Policy")
    end)
    |> Enum.flat_map(fn {path, %{content: content, ast: ast}} ->
      if ast do
        extract_policy_module(content, path)
      else
        []
      end
    end)
  end

  defp extract_policy_module(content, path) do
    module_pattern = ~r/defmodule\s+([A-Z][\w.]*Policy)/

    case Regex.run(module_pattern, content) do
      [_, module_name] ->
        # Extract actions defined in this policy
        actions = Regex.scan(~r/def\s+(?:authorize|permit|can\?)\(\s*:(\w+)/, content)
                  |> Enum.map(fn [_, a] -> a end)
                  |> Enum.uniq()

        [%{
          module: module_name,
          path: path,
          actions: actions,
          context: extract_context(path)
        }]
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Auth Plug Extraction
  # ---------------------------------------------------------------------------

  defp extract_auth_plugs(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{content: content}} ->
      extract_auth_plugs_from_content(content, path)
    end)
    |> Enum.uniq_by(& &1.plug)
  end

  defp extract_auth_plugs_from_content(content, path) do
    # Common auth plug patterns
    patterns = [
      ~r/plug\s+:require_authenticated/,
      ~r/plug\s+:authorize/,
      ~r/plug\s+:ensure_/,
      ~r/plug\s+:check_/,
      ~r/plug\s+:verify_/,
      ~r/plug\s+([A-Z][\w.]*Auth[\w]*)/,
      ~r/plug\s+([A-Z][\w.]*\.Authorize)/
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, content)
      |> Enum.map(fn
        [full_match] -> %{plug: String.trim(full_match), path: path, context: extract_context(path)}
        [_full, module] -> %{plug: module, path: path, context: extract_context(path)}
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_values(str) do
    cond do
      String.starts_with?(str, "~w") ->
        str
        |> String.replace(~r/~w\(|\)a?/, "")
        |> String.split(~r/\s+/, trim: true)

      String.starts_with?(str, "[") ->
        str
        |> String.replace(~r/[\[\]]/, "")
        |> String.split(",")
        |> Enum.map(fn s ->
          s |> String.trim() |> String.replace(~r/^:|^"|"$/, "")
        end)
        |> Enum.reject(&(&1 == ""))

      true ->
        []
    end
  end

  defp extract_context(path) do
    path
    |> Path.basename(".ex")
    |> Macro.camelize()
  end
end
