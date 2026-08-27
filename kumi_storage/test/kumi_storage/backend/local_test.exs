defmodule KumiStorage.Backend.LocalTest do
  # No DB — Local is pure filesystem I/O against a tmp root per test.
  use ExUnit.Case, async: true

  alias KumiStorage.Backend.Local

  setup do
    root = Path.join(System.tmp_dir!(), "kumi_storage_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{opts: [root: root], root: root}
  end

  describe "store/4 + path/2 + open/2 round trip" do
    test "stores binary content and can be read back", %{opts: opts} do
      assert {:ok, key} = Local.store({:binary, "hello world"}, "photo.jpg", "image/jpeg", opts)
      assert {:ok, path} = Local.path(key, opts)
      assert File.read!(path) == "hello world"

      assert {:ok, io} = Local.open(key, opts)
      assert IO.binread(io, :eof) == "hello world"
      File.close(io)
    end

    test "stores from a source path (e.g. a Plug.Upload tmp file)", %{opts: opts} do
      tmp = Path.join(System.tmp_dir!(), "upload_source_#{System.unique_integer([:positive])}")
      File.write!(tmp, "from disk")
      on_exit(fn -> File.rm(tmp) end)

      assert {:ok, key} = Local.store({:path, tmp}, "scan.png", "image/png", opts)
      assert {:ok, path} = Local.path(key, opts)
      assert File.read!(path) == "from disk"
    end

    test "the on-disk key never contains the client-supplied filename", %{opts: opts} do
      assert {:ok, key} =
               Local.store({:binary, "x"}, "very-identifying-name.png", "image/png", opts)

      refute key =~ "very-identifying-name"
      assert key =~ ~r/^[0-9a-f-]{36}\.png$/
    end

    test "keeps a sanitized extension, drops an unrecognized/dangerous one", %{opts: opts} do
      {:ok, key} = Local.store({:binary, "x"}, "a.PNG", "image/png", opts)
      assert String.ends_with?(key, ".png")

      {:ok, key2} = Local.store({:binary, "x"}, "../../etc/passwd", "image/png", opts)
      refute key2 =~ "/"
      refute key2 =~ ".."
    end
  end

  describe "delete/2" do
    test "removes the stored file", %{opts: opts} do
      {:ok, key} = Local.store({:binary, "bye"}, "f.jpg", "image/jpeg", opts)
      assert {:ok, path} = Local.path(key, opts)
      assert File.exists?(path)

      assert :ok = Local.delete(key, opts)
      refute File.exists?(path)
    end

    test "deleting an already-missing key is not an error", %{opts: opts} do
      {:ok, key} = Local.store({:binary, "bye"}, "f.jpg", "image/jpeg", opts)
      Local.delete(key, opts)

      assert :ok = Local.delete(key, opts)
    end
  end

  describe "traversal rejection" do
    test "path/2 rejects a key that escapes the root via ../..", %{opts: opts} do
      assert Local.path("../../etc/passwd", opts) == :error
    end

    test "path/2 rejects an absolute-path-looking key from escaping (stays contained)", %{
      opts: opts,
      root: root
    } do
      # Path.join/2 never lets an "absolute" second segment override the
      # first (unlike Erlang's :filename.join) — so this resolves inside
      # root, which is safe, not a traversal.
      assert {:ok, path} = Local.path("/etc/passwd", opts)
      assert String.starts_with?(path, Path.expand(root))
    end

    test "delete/2 and open/2 also reject an escaping key", %{opts: opts} do
      assert {:error, :invalid_key} = Local.delete("../secret", opts)
      assert {:error, :invalid_key} = Local.open("../secret", opts)
    end
  end
end
