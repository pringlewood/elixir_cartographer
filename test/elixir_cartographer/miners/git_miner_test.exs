defmodule ElixirCartographer.Miners.GitMinerTest do
  use ExUnit.Case, async: true

  alias ElixirCartographer.Miners.GitMiner

  describe "empty/0" do
    test "returns zeroed git data" do
      data = GitMiner.empty()
      assert data.total_commits == 0
      assert data.hotspots == []
      assert data.commit_types == %{}
      assert data.recent_activity == []
      assert data.contributors == []
    end
  end

  describe "classify_commits/1" do
    test "classifies commits from a real git repo" do
      # Use the elixir_cartographer repo itself (or any git repo)
      project_path = Path.expand("../../..", __DIR__)

      if File.dir?(Path.join(project_path, ".git")) do
        types = GitMiner.classify_commits(project_path)
        assert is_map(types)
      end
    end
  end

  describe "analyze/1" do
    test "works with a valid git repo" do
      # Test against the elixir_cartographer project itself
      project_path = Path.expand("../../..", __DIR__)
      config = %ElixirCartographer.Config{
        project_path: project_path,
        lib_path: Path.join(project_path, "lib"),
        test_path: Path.join(project_path, "test"),
        config_path: Path.join(project_path, "config"),
        mix_exs_path: Path.join(project_path, "mix.exs")
      }

      if File.dir?(Path.join(project_path, ".git")) do
        result = GitMiner.analyze(config)
        assert result.total_commits >= 0
        assert is_list(result.hotspots)
        assert is_map(result.commit_types)
      end
    end

    test "returns empty for non-git directory" do
      config = %ElixirCartographer.Config{
        project_path: System.tmp_dir!(),
        lib_path: Path.join(System.tmp_dir!(), "lib"),
        test_path: Path.join(System.tmp_dir!(), "test"),
        config_path: Path.join(System.tmp_dir!(), "config"),
        mix_exs_path: Path.join(System.tmp_dir!(), "mix.exs")
      }

      result = GitMiner.analyze(config)
      assert result.total_commits == 0
    end
  end

  describe "find_hotspots/1" do
    test "returns list of hotspot maps" do
      project_path = Path.expand("../../..", __DIR__)

      if File.dir?(Path.join(project_path, ".git")) do
        hotspots = GitMiner.find_hotspots(project_path)
        assert is_list(hotspots)

        if hotspots != [] do
          assert Map.has_key?(hd(hotspots), :file)
          assert Map.has_key?(hd(hotspots), :fix_count)
        end
      end
    end
  end
end
