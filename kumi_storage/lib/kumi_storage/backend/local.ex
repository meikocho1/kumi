defmodule KumiStorage.Backend.Local do
  @moduledoc """
  Filesystem `KumiStorage.Backend` (blueprint §6 point 7). Takes its
  storage root via `opts[:root]` — never reads Application config itself
  (see `KumiStorage.Backend` moduledoc).

  Keys are UUID-based, generated here — the client-supplied filename is
  NEVER used to build the on-disk path, not even for its extension: the
  stored extension is derived from the validated `content_type` instead
  (see `ext_for_content_type/1`), so the allowlist governs what gets
  served, not whatever suffix the client's filename happened to have.
  `path/2`, `delete/2`, and `open/2` all
  re-resolve the key against the root and reject anything that would
  escape it (`../..`, absolute-path tricks, etc.) via `Path.expand/1` +
  a prefix check — the same guard `KumiStorage.Plug` relies on to 404
  traversal attempts instead of serving arbitrary files.
  """

  @behaviour KumiStorage.Backend

  # filename stays in the signature — it's part of the KumiStorage.Backend
  # behaviour callback — but is otherwise unused: the stored extension
  # comes from content_type (see ext_for_content_type/1 below), not from
  # whatever extension the client's filename happened to carry.
  @impl true
  def store(source, _filename, content_type, opts) do
    root = fetch_root!(opts)
    key = "#{Ash.UUID.generate()}#{ext_for_content_type(content_type)}"
    dest = Path.join(root, key)

    with :ok <- File.mkdir_p(root),
         :ok <- write(source, dest) do
      {:ok, key}
    end
  end

  @impl true
  def delete(key, opts) do
    case path(key, opts) do
      {:ok, path} ->
        case File.rm(path) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, :invalid_key}
    end
  end

  @impl true
  def path(key, opts) do
    root = opts |> fetch_root!() |> Path.expand()
    candidate = Path.expand(Path.join(root, key))

    if candidate == root or String.starts_with?(candidate, root <> "/") do
      {:ok, candidate}
    else
      :error
    end
  end

  @impl true
  def open(key, opts) do
    case path(key, opts) do
      {:ok, path} -> File.open(path, [:read, :binary])
      :error -> {:error, :invalid_key}
    end
  end

  defp fetch_root!(opts), do: Keyword.fetch!(opts, :root)

  defp write({:path, source_path}, dest), do: File.cp(source_path, dest)
  defp write({:binary, data}, dest), do: File.write(dest, data)

  # The stored extension is derived from the *validated* content type, never
  # from the client-supplied filename — a filename is just a label the
  # client attaches and proves nothing about the bytes. Deriving from
  # content_type means the allowlist in KumiStorage.Validation (which the
  # caller must run before store/4) is what actually governs what
  # KumiStorage.Plug will later serve: MIME.from_path/1 on the resulting
  # key can only land on one of these types, or on no match at all.
  #
  # A content type outside this map — including one from a caller-supplied
  # `:allowed_content_types` override — gets no extension at all. That's
  # deliberate fail-closed behaviour: without a matching extension,
  # MIME.from_path/1 can't identify the file, so the Plug serves it as
  # application/octet-stream instead of live content.
  @content_type_ext %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }

  defp ext_for_content_type(content_type), do: Map.get(@content_type_ext, content_type, "")
end
