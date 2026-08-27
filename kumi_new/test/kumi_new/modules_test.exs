defmodule KumiNew.ModulesTest do
  use ExUnit.Case, async: true

  alias KumiNew.Modules

  describe "catalog/0" do
    test "has a storage entry with the expected dep and installer" do
      assert %Modules.Entry{
               key: :storage,
               dep: :kumi_storage,
               installer: "kumi_storage.install"
             } = Modules.fetch(:storage)
    end

    test "keys/0 lists all catalog keys" do
      assert Modules.keys() == [:storage]
    end

    test "describe_catalog/0 names each entry with its description" do
      assert Modules.describe_catalog() =~ "storage — File/image uploads (kumi_storage)"
    end
  end

  describe "parse_selection/1 (shared by --with and the interactive prompt answer)" do
    test "parses a single known module" do
      assert Modules.parse_selection("storage") == {:ok, [:storage]}
    end

    test "empty string selects nothing" do
      assert Modules.parse_selection("") == {:ok, []}
    end

    test "blank/whitespace-only string selects nothing" do
      assert Modules.parse_selection("   ") == {:ok, []}
    end

    test "trims whitespace around comma-separated tokens" do
      assert Modules.parse_selection(" storage , storage ") == {:ok, [:storage]}
    end

    test "unknown module errors, naming the catalog" do
      assert {:error, message} = Modules.parse_selection("mail")
      assert message =~ "unknown module(s): mail"
      assert message =~ "storage — File/image uploads (kumi_storage)"
    end

    test "a mix of known and unknown reports only the unknown ones" do
      assert {:error, message} = Modules.parse_selection("storage,mail,chat")
      assert message =~ "unknown module(s): mail, chat"
      refute message =~ "unknown module(s): storage"
    end
  end

  describe "prompt_text/0" do
    test "shows the catalog keys as a bracketed hint" do
      assert Modules.prompt_text() ==
               "Modules to include (comma-separated, empty for none) [storage]: "
    end
  end

  describe "resolve/1 (no I/O for decided flags)" do
    test "{:with, list} resolves as-is" do
      assert Modules.resolve({:with, [:storage]}) == {:ok, [:storage]}
    end

    test ":none resolves to no modules" do
      assert Modules.resolve(:none) == {:ok, []}
    end
  end
end
