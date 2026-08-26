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
               "--json-api"
             ])

    assert args.db_port == 5434
    assert args.admin? == false
    assert args.setup? == false
    assert args.json_api? == true
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
end
