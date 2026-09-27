defmodule KumiStorage.PlugTest do
  # No DB — serves straight off a tmp filesystem root via the real
  # KumiStorage.Backend.Local, configured the way the installer's router
  # forward does it: through the Attachment's __kumi_storage_config__/0
  # (here the test/support one, which reads this test process's config).
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias KumiStorage.Backend.Local

  @opts KumiStorage.Plug.init(config: {KumiStorage.Test.Attachment, :__kumi_storage_config__})

  setup do
    root =
      Path.join(System.tmp_dir!(), "kumi_storage_plug_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Process.put(:kumi_storage_test_config, {Local, [root: root]})

    %{root: root}
  end

  test "serves a stored file with the right content-type", %{root: root} do
    {:ok, key} = Local.store({:binary, "png-bytes"}, "avatar.png", "image/png", root: root)

    conn = conn(:get, "/uploads/#{key}") |> Map.put(:path_info, [key])
    conn = KumiStorage.Plug.call(conn, @opts)

    assert conn.status == 200
    assert conn.resp_body == "png-bytes"
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "resolves the config on every request, not at init" do
    other_root =
      Path.join(System.tmp_dir!(), "kumi_storage_plug_test_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(other_root) end)
    {:ok, key} = Local.store({:binary, "later"}, "a.png", "image/png", root: other_root)
    Process.put(:kumi_storage_test_config, {Local, [root: other_root]})

    conn = conn(:get, "/uploads/#{key}") |> Map.put(:path_info, [key])
    conn = KumiStorage.Plug.call(conn, @opts)

    assert conn.status == 200
    assert conn.resp_body == "later"
  end

  test "404s on a missing key" do
    conn =
      conn(:get, "/uploads/does-not-exist.png") |> Map.put(:path_info, ["does-not-exist.png"])

    conn = KumiStorage.Plug.call(conn, @opts)

    assert conn.status == 404
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "404s on a traversal attempt instead of serving an arbitrary file" do
    conn =
      conn(:get, "/uploads/..%2F..%2Fetc%2Fpasswd")
      |> Map.put(:path_info, ["../../etc/passwd"])

    conn = KumiStorage.Plug.call(conn, @opts)

    assert conn.status == 404
  end

  test "404s when more than one path segment is given" do
    conn = conn(:get, "/uploads/a/b") |> Map.put(:path_info, ["a", "b"])
    conn = KumiStorage.Plug.call(conn, @opts)

    assert conn.status == 404
  end

  describe "init/1" do
    test "requires config: {module, function}, naming the installer's snippet" do
      for opts <- [[], [config: KumiStorage.Test.Attachment], [config: {"M", :f}]] do
        error = assert_raise ArgumentError, fn -> KumiStorage.Plug.init(opts) end
        assert error.message =~ "config: {MyApp.Core.Attachment, :__kumi_storage_config__}"
      end
    end
  end
end
