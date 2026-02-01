defmodule ElixirCartographerTest do
  use ExUnit.Case

  describe "map/2" do
    test "runs full pipeline on fixtures directory" do
      fixtures_path = Path.expand("fixtures", __DIR__)
      output_path = Path.join(System.tmp_dir!(), "cart_integ_#{:rand.uniform(999999)}")

      # Need to create a minimal project-like structure
      tmp = Path.join(System.tmp_dir!(), "cart_project_#{:rand.uniform(999999)}")
      lib_path = Path.join(tmp, "lib/sample_app")
      test_path = Path.join(tmp, "test")
      config_path = Path.join(tmp, "config")

      File.mkdir_p!(lib_path)
      File.mkdir_p!(test_path)
      File.mkdir_p!(config_path)

      # Copy fixtures into lib structure
      for file <- Path.wildcard(Path.join(fixtures_path, "*.ex")) do
        File.cp!(file, Path.join(lib_path, Path.basename(file)))
      end

      # Copy test fixture
      test_fixture = Path.join(fixtures_path, "sample_test.exs")
      if File.exists?(test_fixture) do
        File.cp!(test_fixture, Path.join(test_path, "sample_module_test.exs"))
      end

      # Copy config fixture
      config_fixture = Path.join(fixtures_path, "sample_config.exs")
      if File.exists?(config_fixture) do
        File.cp!(config_fixture, Path.join(config_path, "config.exs"))
      end

      # Write mix.exs
      File.write!(Path.join(tmp, "mix.exs"), """
      defmodule SampleApp.MixProject do
        use Mix.Project
        def project, do: [app: :sample_app]
      end
      """)

      # Init git repo for git mining
      System.cmd("git", ["init"], cd: tmp)
      System.cmd("git", ["config", "user.email", "test@test.com"], cd: tmp)
      System.cmd("git", ["config", "user.name", "Test"], cd: tmp)
      System.cmd("git", ["add", "."], cd: tmp)
      System.cmd("git", ["commit", "-m", "feat: initial commit"], cd: tmp)

      # Run the cartographer
      {:ok, _analysis} = ElixirCartographer.map(tmp, output: output_path)

      # Verify output
      assert File.exists?(Path.join(output_path, "AGENTS.md"))
      assert File.dir?(Path.join(output_path, "contexts"))

      agents_md = File.read!(Path.join(output_path, "AGENTS.md"))
      assert String.contains?(agents_md, "AGENTS.md")
      assert String.contains?(agents_md, "Project Overview")
      assert String.contains?(agents_md, "Domain Contexts")
      assert String.contains?(agents_md, "Data Model")

      # Cleanup
      File.rm_rf!(tmp)
      File.rm_rf!(output_path)
    end
  end
end
