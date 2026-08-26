defmodule KumiNew.InjectTest do
  use ExUnit.Case, async: true

  alias KumiNew.Inject

  @fixtures_dir Path.join(__DIR__, "../fixtures")
  @mix_exs File.read!(Path.join(@fixtures_dir, "generated_mix.exs"))
  @dev_exs File.read!(Path.join(@fixtures_dir, "generated_dev.exs"))
  @test_exs File.read!(Path.join(@fixtures_dir, "generated_test_config.exs"))

  describe "insert_deps/3" do
    test "inserts kumi and kumi_admin as the first deps, admin? true" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", true)
      assert updated =~ ~s[{:kumi, path: "/abs/kumi_path/kumi"}]
      assert updated =~ ~s[{:kumi_admin, path: "/abs/kumi_path/kumi_admin"}]

      # kumi comes before the existing deps, kumi_admin comes right after kumi
      [_, rest] = String.split(updated, ~s[{:kumi, path:])
      assert rest =~ ~s[{:kumi_admin, path:]

      # existing deps list is untouched otherwise
      assert updated =~ ~s[{:bcrypt_elixir, "~> 3.0"}]
    end

    test "omits kumi_admin when admin? is false" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", false)
      assert updated =~ ~s[{:kumi, path: "/abs/kumi_path/kumi"}]
      refute updated =~ "kumi_admin"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", true)
      assert {:ok, _quoted} = Code.string_to_quoted(updated)
    end

    test "errors loudly when the anchor is absent" do
      assert {:error, message} = Inject.insert_deps("defmodule Foo do\nend\n", "/x", true)
      assert message =~ "could not find"
    end
  end

  describe "patch_port/2" do
    test "inserts port: PORT right after hostname in dev.exs" do
      assert {:ok, updated} = Inject.patch_port(@dev_exs, 5434)
      assert updated =~ "hostname: \"localhost\",\n  port: 5434,\n"
    end

    test "inserts port: PORT right after hostname in test.exs" do
      assert {:ok, updated} = Inject.patch_port(@test_exs, 5434)
      assert updated =~ "hostname: \"localhost\",\n  port: 5434,\n"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, updated} = Inject.patch_port(@dev_exs, 5434)
      assert {:ok, _quoted} = Code.string_to_quoted(updated)
    end

    test "errors loudly when the anchor is absent" do
      assert {:error, message} = Inject.patch_port("config :x, Y, []\n", 5434)
      assert message =~ "could not find"
    end
  end
end
