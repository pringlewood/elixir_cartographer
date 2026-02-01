defmodule ElixirCartographer.Miners.TestMinerTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Miners.TestMiner

  describe "empty/0" do
    test "returns zeroed test data" do
      data = TestMiner.empty()
      assert data.total_tests == 0
      assert data.test_files == []
      assert data.edge_cases == []
      assert data.coverage_gaps == []
    end
  end

  describe "analyze/1" do
    test "mines test files from this project" do
      project_path = Path.expand("../../..", __DIR__)
      config = %ElixirCartographer.Config{
        project_path: project_path,
        lib_path: Path.join(project_path, "lib"),
        test_path: Path.join(project_path, "test"),
        config_path: Path.join(project_path, "config"),
        mix_exs_path: Path.join(project_path, "mix.exs")
      }

      result = TestMiner.analyze(config)
      assert result.total_tests > 0
      assert length(result.test_files) > 0
    end

    test "handles missing test directory" do
      config = %ElixirCartographer.Config{
        project_path: "/tmp/nonexistent_xyz",
        lib_path: "/tmp/nonexistent_xyz/lib",
        test_path: "/tmp/nonexistent_xyz/test",
        config_path: "/tmp/nonexistent_xyz/config",
        mix_exs_path: "/tmp/nonexistent_xyz/mix.exs"
      }

      result = TestMiner.analyze(config)
      assert result == TestMiner.empty()
    end
  end

  describe "extract_edge_cases/1" do
    test "identifies error and edge case tests" do
      test_data = [
        %{
          path: "test/user_test.exs",
          module: "UserTest",
          tests: [
            %{description: "returns error when email is missing", type: :error_case},
            %{description: "handles edge case of empty list", type: :edge_case},
            %{description: "creates a valid user", type: :happy_path}
          ],
          describes: [],
          test_count: 3
        }
      ]

      cases = TestMiner.extract_edge_cases(test_data)
      assert length(cases) == 2

      types = Enum.map(cases, & &1.type)
      assert :error_case in types
      assert :edge_case in types
    end
  end

  describe "find_coverage_gaps/2" do
    test "identifies modules without tests" do
      # Create temp structure
      tmp = Path.join(System.tmp_dir!(), "cart_cov_#{:rand.uniform(999999)}")
      lib = Path.join(tmp, "lib")
      test = Path.join(tmp, "test")

      File.mkdir_p!(lib)
      File.mkdir_p!(test)

      File.write!(Path.join(lib, "user.ex"), "defmodule User do end")
      File.write!(Path.join(lib, "order.ex"), "defmodule Order do end")
      File.write!(Path.join(test, "user_test.exs"), "defmodule UserTest do end")
      # No order_test.exs!

      gaps = TestMiner.find_coverage_gaps(lib, test)
      gap_files = Enum.map(gaps, & &1.file)

      assert Enum.any?(gap_files, &String.contains?(&1, "order.ex"))
      refute Enum.any?(gap_files, &String.contains?(&1, "user.ex"))

      File.rm_rf!(tmp)
    end
  end
end
