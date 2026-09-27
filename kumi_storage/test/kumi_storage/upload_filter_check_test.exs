defmodule KumiStorage.UploadFilterCheckTest do
  # A create authorized by a filter, which Ash checks against the inserted
  # row inside the transaction. Not async: the tests share one Mnesia
  # table, and Mnesia reruns a transaction that hits another's lock.
  use ExUnit.Case, async: false

  alias KumiStorage.Backend.Local
  alias KumiStorage.Test.MnesiaAttachment

  setup_all do
    # Ash lists :mnesia in its extra_applications, so it is running.
    {:atomic, :ok} = :mnesia.create_table(MnesiaAttachment, attributes: [:_pkey, :val])
    on_exit(fn -> :mnesia.delete_table(MnesiaAttachment) end)
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "kumi_storage_upload_filter_check_test_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    Process.put(:kumi_storage_test_config, {Local, root: root})

    %{root: root}
  end

  defp upload(filename, actor) do
    Ash.create(
      MnesiaAttachment,
      %{source: {:binary, "png-bytes"}, filename: filename, content_type: "image/png"},
      action: :upload,
      actor: actor
    )
  end

  defp stored_files(root), do: if(File.dir?(root), do: File.ls!(root), else: [])

  test "a filter the inserted row passes authorizes the upload", %{root: root} do
    assert {:ok, attachment} = upload("accepted.png", %{max_bytes: 100})

    assert {:ok, path} = Local.path(attachment.storage_key, root: root)
    assert File.read!(path) == "png-bytes"
  end

  test "a filter the inserted row fails rolls the create back and deletes the file",
       %{root: root} do
    assert {:error, %Ash.Error.Forbidden{}} = upload("rejected.png", %{max_bytes: 1})

    # The root exists, so store/4 did run; the cleanup emptied it.
    assert File.dir?(root)
    assert stored_files(root) == []
    refute "rejected.png" in Enum.map(Ash.read!(MnesiaAttachment), & &1.filename)
    refute Enum.any?(Process.get_keys(), &match?({KumiStorage.Upload, _}, &1))
  end
end
