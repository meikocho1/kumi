defmodule KumiNew.ArgsTest do
  use ExUnit.Case, async: true

  alias KumiNew.Args

  setup do
    dir = Path.join(System.tmp_dir!(), "kumi_new_args_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "kumi"))
    File.mkdir_p!(Path.join(dir, "kumi_admin"))
    File.write!(Path.join(dir, "kumi/mix.exs"), "")
    File.write!(Path.join(dir, "kumi_admin/mix.exs"), "")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{kumi_path: dir}
  end

  test "parses required app_name and kumi_path with defaults", %{kumi_path: path} do
    assert {:ok, args} = Args.parse(["my_crm", "--kumi-path", path])
    assert args.app_name == "my_crm"
    assert args.kumi_path == path
    assert args.db_port == 5432
    assert args.admin? == true
    assert args.setup? == true
    assert args.json_api? == false
    assert args.auth_strategies == ["password"]
  end

  test "parses all flags", %{kumi_path: path} do
    assert {:ok, args} =
             Args.parse([
               "my_crm",
               "--kumi-path",
               path,
               "--db-port",
               "5434",
               "--no-admin",
               "--no-setup",
               "--json-api",
               "--auth-strategy",
               "password,magic_link"
             ])

    assert args.db_port == 5434
    assert args.admin? == false
    assert args.setup? == false
    assert args.json_api? == true
    assert args.auth_strategies == ["password", "magic_link"]
  end

  test "rejects an auth strategy ash_authentication cannot generate", %{kumi_path: path} do
    assert {:error, message} =
             Args.parse(["my_crm", "--kumi-path", path, "--auth-strategy", "google"])

    assert message =~ "unknown --auth-strategy value(s): google"
    assert message =~ "auth guide"
  end

  test "errors when --kumi-path is missing" do
    assert {:error, message} = Args.parse(["my_crm"])
    assert message =~ "--kumi-path is required"
  end

  test "errors when --kumi-path does not contain kumi/mix.exs" do
    assert {:error, message} = Args.parse(["my_crm", "--kumi-path", System.tmp_dir!()])
    assert message =~ "kumi/mix.exs"
  end

  test "errors when app_name is missing" do
    assert {:error, message} = Args.parse(["--kumi-path", "/tmp"])
    assert message =~ "APP_NAME"
  end

  test "errors on invalid app_name", %{kumi_path: path} do
    assert {:error, message} = Args.parse(["MyCrm", "--kumi-path", path])
    assert message =~ "lowercase"
  end

  test "no --with/--no-modules flags -> modules_flag is :unset", %{kumi_path: path} do
    assert {:ok, args} = Args.parse(["my_crm", "--kumi-path", path])
    assert args.modules_flag == :unset
    assert args.modules == []
  end

  test "--with storage -> modules_flag is {:with, [:storage]}", %{kumi_path: path} do
    assert {:ok, args} = Args.parse(["my_crm", "--kumi-path", path, "--with", "storage"])
    assert args.modules_flag == {:with, [:storage]}
  end

  test "--with with an unknown module errors, naming the catalog", %{kumi_path: path} do
    assert {:error, message} =
             Args.parse(["my_crm", "--kumi-path", path, "--with", "storage,mail"])

    assert message =~ "unknown module(s): mail"
    assert message =~ "storage — File/image uploads (kumi_storage)"
  end

  test "--no-modules -> modules_flag is :none", %{kumi_path: path} do
    assert {:ok, args} = Args.parse(["my_crm", "--kumi-path", path, "--no-modules"])
    assert args.modules_flag == :none
  end

  test "--with combined with --no-modules errors", %{kumi_path: path} do
    assert {:error, message} =
             Args.parse(["my_crm", "--kumi-path", path, "--with", "storage", "--no-modules"])

    assert message =~ "cannot combine --with with --no-modules"
  end
end
