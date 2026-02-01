defmodule ElixirCartographer.AstUtils do
  @moduledoc """
  Shared utilities for safe AST manipulation.
  """

  @doc """
  Convert AST module name parts to a string safely.
  Handles atoms, __MODULE__ references, and other AST nodes.
  """
  def parts_to_string(parts) when is_list(parts) do
    parts
    |> Enum.map(fn
      part when is_atom(part) -> to_string(part)
      {:__MODULE__, _, _} -> "__MODULE__"
      {name, _, _} when is_atom(name) -> to_string(name)
      other -> inspect(other)
    end)
    |> Enum.join(".")
  end

  def parts_to_string(_), do: "unknown"
end
