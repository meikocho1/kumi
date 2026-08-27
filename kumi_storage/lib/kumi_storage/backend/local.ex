defmodule KumiStorage.Backend.Local do
  @moduledoc """
  Filesystem `KumiStorage.Backend` (blueprint §6 point 7). Takes its
  storage root via `opts[:root]` — never reads Application config itself
  (see `KumiStorage.Backend` moduledoc).

  Keys are UUID-based, generated here — the client-supplied filename is
  NEVER used to build the on-disk path (only its extension, sanitized to
  a short alnum suffix, is kept). `path/2`, `delete/2`, and `open/2` all
  re-resolve the key against the root and reject anything that would
  escape it (`../..`, absolute-path tricks, etc.) via `Path.expand/1` +
  a prefix check — the same guard `KumiStorage.Plug` relies on to 404
  traversal attempts instead of serving arbitrary files.
  """

  @behaviour KumiStorage.Backend

  @impl true
  def store(source, filename, _content_type, opts) do
    root = fetch_root!(opts)
    key = "#{Ash.UUID.generate()}#{sanitized_ext(filename)}"
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

  # ponytail: alnum-only, length-capped extension — good enough to keep
  # keys readable and traversal-proof; not a MIME-vs-extension validator
  # (that's KumiStorage.Validation's job, upstream of store/4).
  defp sanitized_ext(filename) do
    ext = filename |> Path.extname() |> String.downcase()

    if Regex.match?(~r/^\.[a-z0-9]{1,10}$/, ext) do
      ext
    else
      ""
    end
  end
end
