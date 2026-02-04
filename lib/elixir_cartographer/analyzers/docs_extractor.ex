defmodule ElixirCartographer.Analyzers.DocsExtractor do
  @moduledoc """
  Extracts @moduledoc and @doc documentation from Elixir source files.
  
  Used to enrich user-facing documentation with actual developer comments.
  """

  @doc """
  Analyze parsed files and extract documentation.
  """
  def analyze(parsed_files) do
    parsed_files
    |> Enum.flat_map(fn {path, %{content: content}} ->
      extract_docs_from_content(content, path)
    end)
  end

  defp extract_docs_from_content(content, path) do
    module_docs = extract_module_docs(content, path)
    function_docs = extract_function_docs(content, path)
    
    module_docs ++ function_docs
  end

  # ---------------------------------------------------------------------------
  # Module Doc Extraction
  # ---------------------------------------------------------------------------

  defp extract_module_docs(content, path) do
    # Match defmodule followed by @moduledoc
    pattern = ~r/defmodule\s+([A-Z][\w.]+)\s+do\s+(?:use\s+[^\n]+\s+)?(?:import\s+[^\n]+\s+)?(?:alias\s+[^\n]+\s+)?@moduledoc\s+(?:~[sS])?\"{3}([\s\S]*?)\"{3}/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, module_name, doc_content] ->
      %{
        type: :module,
        module: module_name,
        path: path,
        doc: clean_doc(doc_content),
        summary: extract_summary(doc_content)
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Function Doc Extraction
  # ---------------------------------------------------------------------------

  defp extract_function_docs(content, path) do
    # Match @doc followed by def
    pattern = ~r/@doc\s+(?:~[sS])?\"{3}([\s\S]*?)\"{3}\s+def\s+(\w+)/

    Regex.scan(pattern, content)
    |> Enum.map(fn [_, doc_content, function_name] ->
      # Try to get the module name from the file
      module_name = extract_module_name(content)
      
      %{
        type: :function,
        module: module_name,
        function: function_name,
        path: path,
        doc: clean_doc(doc_content),
        summary: extract_summary(doc_content)
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
      [_, name] -> name
      _ -> "Unknown"
    end
  end

  defp clean_doc(doc) do
    doc
    |> String.trim()
    |> String.replace(~r/\n\s{2,}/, "\n")  # Normalize indentation
  end

  defp extract_summary(doc) do
    doc
    |> String.trim()
    |> String.split(~r/\n\n|\n##/, parts: 2)
    |> List.first()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(200)
  end

  defp truncate(str, max_len) do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len - 3) <> "..."
    else
      str
    end
  end

  @doc """
  Get documentation for a specific module.
  """
  def get_module_doc(docs, module_name) do
    docs
    |> Enum.find(fn d -> d.type == :module && String.ends_with?(d.module, module_name) end)
  end

  @doc """
  Get documentation for functions in a module.
  """
  def get_function_docs(docs, module_name) do
    docs
    |> Enum.filter(fn d -> 
      d.type == :function && String.ends_with?(d.module, module_name)
    end)
  end

  @doc """
  Build a lookup map for quick access: module_name -> %{module_doc, functions: [...]}
  """
  def build_lookup(docs) do
    # Group by module
    by_module = Enum.group_by(docs, & &1.module)
    
    by_module
    |> Enum.map(fn {module, entries} ->
      module_doc = Enum.find(entries, fn e -> e.type == :module end)
      function_docs = Enum.filter(entries, fn e -> e.type == :function end)
      
      {module, %{
        module_doc: module_doc,
        functions: function_docs
      }}
    end)
    |> Map.new()
  end
end
