defmodule ElixirCartographer.ConfigTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Config

  describe "new/2" do
    test "creates config with defaults" do
      config = Config.new("/tmp/fake_project")

      assert config.project_path == "/tmp/fake_project"
      assert config.output_path == "/tmp/fake_project/cartographer_docs"
      assert config.lib_path == "/tmp/fake_project/lib"
      assert config.test_path == "/tmp/fake_project/test"
      assert config.skip_git == false
      assert config.skip_tests == false
    end

    test "respects output option" do
      config = Config.new("/tmp/fake", output: "/tmp/output")
      assert config.output_path == "/tmp/output"
    end

    test "respects skip options" do
      config = Config.new("/tmp/fake", skip_git: true, skip_tests: true)
      assert config.skip_git == true
      assert config.skip_tests == true
    end

    test "detects project name from mix.exs" do
      # Use the elixir_cartographer project itself
      config = Config.new(Path.expand("../../", __DIR__))
      assert config.project_name == "elixir_cartographer"
    end

    test "falls back to directory name when no mix.exs" do
      config = Config.new("/tmp/my_project")
      assert config.project_name == "my_project"
    end

    test "respects name option" do
      config = Config.new("/tmp/fake", name: "MyApp")
      assert config.project_name == "MyApp"
    end
  end
end
