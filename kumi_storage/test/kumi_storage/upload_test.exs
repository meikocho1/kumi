defmodule KumiStorage.UploadTest do
  # No DB — KumiStorage.Test.Attachment is the generated resource on
  # Ash.DataLayer.Ets, storing into a tmp root per test.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias KumiStorage.Backend.Local
  alias KumiStorage.Test.{Attachment, FlakyBackend}
  alias KumiStorage.Upload

  @invalid_source "must be {:path, path} of a regular file, or {:binary, data}"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "kumi_storage_upload_test_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    use_backend(Local, root: root)

    %{root: root}
  end

  defp use_backend(backend, opts), do: Process.put(:kumi_storage_test_config, {backend, opts})

  defp input(overrides \\ %{}) do
    Map.merge(
      %{source: {:binary, "png-bytes"}, filename: "avatar.png", content_type: "image/png"},
      overrides
    )
  end

  defp upload(overrides \\ %{}, opts \\ []) do
    Ash.create(Attachment, input(overrides), Keyword.put_new(opts, :action, :upload))
  end

  defp stored_files(root), do: if(File.dir?(root), do: File.ls!(root), else: [])

  defp field_error?(%{errors: errors}, field, message) do
    Enum.any?(errors, &(Map.get(&1, :field) == field and &1.message == message))
  end

  describe "measure/1" do
    test "a binary is measured by its byte size" do
      assert Upload.measure({:binary, "héllo"}) == {:ok, 6}
    end

    test "a path is measured with File.stat", %{root: root} do
      File.mkdir_p!(root)
      path = Path.join(root, "source")
      File.write!(path, String.duplicate("x", 42))

      assert Upload.measure({:path, path}) == {:ok, 42}
      assert Upload.measure({:path, Path.join(root, "missing")}) == {:error, :enoent}
    end

    test "a path that isn't a regular file is an invalid source", %{root: root} do
      File.mkdir_p!(root)

      assert Upload.measure({:path, root}) == {:error, :invalid_source}
    end

    # File.stat/1 says /dev/zero is 0 bytes; a copy of it never ends.
    if File.exists?("/dev/zero") do
      test "a device is an invalid source, whatever size it reports" do
        assert Upload.measure({:path, "/dev/zero"}) == {:error, :invalid_source}
      end
    end

    test "any other shape is an invalid source" do
      for source <- ["/etc/passwd", %{path: "/tmp/x"}, {:path, 123}, {:binary, 123}, nil] do
        assert Upload.measure(source) == {:error, :invalid_source}
      end
    end
  end

  describe ":upload" do
    test "stores the bytes, and sets the allow_nil? false storage_key before Ash's required check",
         %{root: root} do
      assert {:ok, attachment} = upload()

      assert attachment.filename == "avatar.png"
      assert attachment.content_type == "image/png"
      assert attachment.byte_size == byte_size("png-bytes")
      assert {:ok, path} = Local.path(attachment.storage_key, root: root)
      assert File.read!(path) == "png-bytes"
    end

    test "a read still loads the private storage_key, so the URL function keeps working" do
      {:ok, attachment} = upload()

      refute Ash.Resource.Info.public_attribute(Attachment, :storage_key)
      assert [%{storage_key: key}] = Ash.read!(Attachment)
      assert key == attachment.storage_key
    end

    test "a :path source is copied and measured", %{root: root} do
      source = Path.join(System.tmp_dir!(), "upload_source_#{System.unique_integer([:positive])}")
      File.write!(source, "from disk")
      on_exit(fn -> File.rm(source) end)

      assert {:ok, attachment} = upload(%{source: {:path, source}})

      assert attachment.byte_size == byte_size("from disk")
      assert {:ok, path} = Local.path(attachment.storage_key, root: root)
      assert File.read!(path) == "from disk"
    end

    test "the stored byte_size is measured, never the declared one" do
      data = String.duplicate("x", 100)

      assert {:ok, attachment} = upload(%{source: {:binary, data}, byte_size: 1})
      assert attachment.byte_size == 100
    end

    test "max_bytes is enforced against the measured size", %{root: root} do
      use_backend(Local, root: root, max_bytes: 50)

      assert {:error, error} =
               upload(%{source: {:binary, String.duplicate("x", 100)}, byte_size: 1})

      assert field_error?(error, :byte_size, "is too large")
      assert stored_files(root) == []
    end

    test "a disallowed content type is an error and leaves the root empty", %{root: root} do
      assert {:error, error} = upload(%{content_type: "text/html"})

      assert field_error?(error, :content_type, "is not an allowed content type")
      assert stored_files(root) == []
    end

    test "a :source of the wrong shape is a changeset error, not a crash", %{root: root} do
      assert {:error, error} = upload(%{source: "/etc/passwd"})

      assert field_error?(error, :source, @invalid_source)
      assert stored_files(root) == []
    end

    test "a :path that isn't a regular file is a :source error, and nothing is copied",
         %{root: root} do
      assert {:error, error} = upload(%{source: {:path, System.tmp_dir!()}})

      assert field_error?(error, :source, @invalid_source)
      # store/4 creates the root; it never ran.
      refute File.dir?(root)
    end

    test "building the changeset stores nothing (a form validate, Ash.can?)", %{root: root} do
      changeset = Ash.Changeset.for_create(Attachment, :upload, input())

      assert changeset.valid?
      assert stored_files(root) == []
    end

    test "a create the policies forbid stores nothing", %{root: root} do
      assert {:error, %Ash.Error.Forbidden{}} = upload(%{}, actor: %{role: :blocked})
      assert stored_files(root) == []
    end

    test "a create that fails after the store deletes the stored file", %{root: root} do
      assert {:error, _} = upload(%{}, action: :upload_then_fail)

      # The root exists, so store/4 did run; the cleanup emptied it.
      assert File.dir?(root)
      assert stored_files(root) == []
    end

    test "a backend failure is a fixed error; the reason only reaches the log", %{root: root} do
      use_backend(FlakyBackend, root: root, fail_store: {:disk_full, "/srv/secret/path"})

      log =
        capture_log(fn ->
          assert {:error, error} = upload()
          assert Enum.any?(error.errors, &(&1.message == "upload failed"))
          refute inspect(error) =~ "/srv/secret/path"
        end)

      assert log =~ "/srv/secret/path"
    end
  end

  describe "destroy" do
    test "deletes the stored file", %{root: root} do
      {:ok, attachment} = upload()
      {:ok, path} = Local.path(attachment.storage_key, root: root)

      assert :ok = Ash.destroy(attachment)
      refute File.exists?(path)
    end

    test "a failing backend delete is logged, and the destroy still succeeds", %{root: root} do
      {:ok, attachment} = upload()
      use_backend(FlakyBackend, root: root, fail_delete: :eacces)

      log = capture_log(fn -> assert :ok = Ash.destroy(attachment) end)

      assert log =~ "#{attachment.storage_key} was not deleted: :eacces"
    end

    test "delete_stored/3 passes a failed result through without deleting", %{root: root} do
      {:ok, attachment} = upload()
      {:ok, path} = Local.path(attachment.storage_key, root: root)

      assert Upload.delete_stored({:error, :boom}, Local, root: root) == {:error, :boom}
      assert File.exists?(path)
    end
  end
end
