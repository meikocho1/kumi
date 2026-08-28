defmodule KumiStorage.PlugTest do
  # No DB — serves straight off a tmp filesystem root via the real
  # KumiStorage.Backend.Local, config-driven the same way the plug would
  # be in a host app.
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias KumiStorage.Backend.Local

  setup do
    root =
      Path.join(System.tmp_dir!(), "kumi_storage_plug_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    original_backend = Application.get_env(:kumi_storage, :backend)
    original_root = Application.get_env(:kumi_storage, :root)
    Application.put_env(:kumi_storage, :backend, Local)
    Application.put_env(:kumi_storage, :root, root)

    on_exit(fn ->
      if original_backend, do: Application.put_env(:kumi_storage, :backend, original_backend)
      if original_root, do: Application.put_env(:kumi_storage, :root, original_root)
    end)

    %{root: root}
  end

  test "serves a stored file with the right content-type", %{root: root} do
    {:ok, key} = Local.store({:binary, "png-bytes"}, "avatar.png", "image/png", root: root)

    conn = conn(:get, "/uploads/#{key}") |> Map.put(:path_info, [key])
    conn = KumiStorage.Plug.call(conn, [])

    assert conn.status == 200
    assert conn.resp_body == "png-bytes"
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "404s on a missing key" do
    conn =
      conn(:get, "/uploads/does-not-exist.png") |> Map.put(:path_info, ["does-not-exist.png"])

    conn = KumiStorage.Plug.call(conn, [])

    assert conn.status == 404
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "404s on a traversal attempt instead of serving an arbitrary file" do
    conn =
      conn(:get, "/uploads/..%2F..%2Fetc%2Fpasswd")
      |> Map.put(:path_info, ["../../etc/passwd"])

    conn = KumiStorage.Plug.call(conn, [])

    assert conn.status == 404
  end

  test "404s when more than one path segment is given" do
    conn = conn(:get, "/uploads/a/b") |> Map.put(:path_info, ["a", "b"])
    conn = KumiStorage.Plug.call(conn, [])

    assert conn.status == 404
  end
end
