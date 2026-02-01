defmodule ElixirCartographer.Analyzers.ConfigMatrixTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Analyzers.ConfigMatrix
  alias ElixirCartographer.Config

  @fixtures_path Path.expand("../../fixtures", __DIR__)

  describe "analyze/1" do
    test "extracts environment variables from config files" do
      # Create a temp config structure
      tmp = create_temp_config()
      config = Config.new(tmp)

      result = ConfigMatrix.analyze(config)

      env_names = Enum.map(result.env_vars, & &1.name)
      assert "DATABASE_USER" in env_names
      assert "DATABASE_PASSWORD" in env_names

      cleanup_temp(tmp)
    end

    test "extracts defaults for env vars" do
      tmp = create_temp_config()
      config = Config.new(tmp)

      result = ConfigMatrix.analyze(config)

      db_user = Enum.find(result.env_vars, &(&1.name == "DATABASE_USER"))
      assert db_user.default == "postgres"

      cleanup_temp(tmp)
    end

    test "extracts app configs" do
      tmp = create_temp_config()
      config = Config.new(tmp)

      result = ConfigMatrix.analyze(config)

      assert Enum.any?(result.app_configs, fn c ->
        c.app == "sample_app" && c.module == "SampleAppWeb.Endpoint"
      end)

      cleanup_temp(tmp)
    end

    test "handles missing config directory" do
      config = Config.new("/tmp/nonexistent_project_xyz")
      result = ConfigMatrix.analyze(config)

      assert result.env_vars == []
      assert result.app_configs == []
    end
  end

  defp create_temp_config do
    tmp = Path.join(System.tmp_dir!(), "cart_test_#{:rand.uniform(999999)}")
    config_dir = Path.join(tmp, "config")
    lib_dir = Path.join(tmp, "lib")
    File.mkdir_p!(config_dir)
    File.mkdir_p!(lib_dir)

    # Copy fixture config
    fixture = File.read!(Path.join(@fixtures_path, "sample_config.exs"))
    File.write!(Path.join(config_dir, "config.exs"), fixture)

    # Write a mix.exs
    File.write!(Path.join(tmp, "mix.exs"), """
    defmodule SampleApp.MixProject do
      use Mix.Project
      def project, do: [app: :sample_app]
    end
    """)

    tmp
  end

  defp cleanup_temp(path) do
    File.rm_rf!(path)
  end
end
