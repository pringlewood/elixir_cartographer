defmodule ElixirCartographer.Analyzers.EctoSchemasTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.EctoSchemas

  @fixture_path Path.expand("../../fixtures/sample_module.ex", __DIR__)

  setup do
    content = File.read!(@fixture_path)
    {:ok, ast} = Code.string_to_quoted(content, file: @fixture_path, columns: true)
    parsed = %{@fixture_path => %{ast: ast, content: content}}
    {:ok, parsed: parsed}
  end

  describe "analyze/1" do
    test "detects Ecto schemas", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      assert length(schemas) >= 1
    end

    test "extracts table name", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))
      assert user_schema.table == "users"
    end

    test "extracts fields", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))
      field_names = Enum.map(user_schema.fields, & &1.name)

      assert :email in field_names
      assert :name in field_names
      assert :status in field_names
      assert :role in field_names
    end

    test "extracts field types", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))
      email_field = Enum.find(user_schema.fields, &(&1.name == :email))

      assert email_field.type == ":string"
    end

    test "extracts timestamps", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))
      field_names = Enum.map(user_schema.fields, & &1.name)

      assert :inserted_at in field_names
      assert :updated_at in field_names
    end

    test "extracts associations", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))

      assert Enum.any?(user_schema.associations, &(&1.type == :belongs_to && &1.name == :organization))
      assert Enum.any?(user_schema.associations, &(&1.type == :has_many && &1.name == :roles))
    end

    test "extracts changesets", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))

      assert :changeset in user_schema.changesets
      assert :registration_changeset in user_schema.changesets
    end

    test "extracts validations", %{parsed: parsed} do
      schemas = EctoSchemas.analyze(parsed)
      user_schema = Enum.find(schemas, &(&1.module == "SampleApp.Accounts.User"))

      validation_types = Enum.map(user_schema.validations, &elem(&1, 0))
      assert :required in validation_types
      assert :format in validation_types
      assert :length in validation_types
      assert :inclusion in validation_types
      assert :unique in validation_types
    end

    test "skips non-schema files" do
      content = """
      defmodule SomeModule do
        def hello, do: :world
      end
      """
      {:ok, ast} = Code.string_to_quoted(content)
      parsed = %{"some.ex" => %{ast: ast, content: content}}

      schemas = EctoSchemas.analyze(parsed)
      assert schemas == []
    end
  end
end
