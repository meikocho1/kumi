defmodule KumiStorage.Backend do
  @moduledoc """
  Behaviour for `Kumi.Storage` storage backends (blueprint §6 point 7).
  `KumiStorage.Backend.Local` (filesystem) is the only v1 implementation —
  an S3 backend is a committed follow-up, not a speculative abstraction.

  Every callback takes `opts` explicitly. Backends never read Application
  config themselves — the caller (e.g. `KumiStorage.Plug`, or the run-2
  LiveView upload consumer) resolves `Application.get_env(:kumi_storage,
  ...)` once, at its own boundary, and passes the result down. This keeps
  backends pure and directly testable (no `Application.put_env` needed in
  their own tests) and matches the repo-wide "library code takes explicit
  args" convention.
  """

  @typedoc "Opaque, backend-assigned identifier for a stored file."
  @type key :: String.t()

  @typedoc """
  What to store. Tagged explicitly because a bare `binary()` is
  ambiguous — it could be a filesystem path (Elixir's `Path.t()` is
  itself just `binary()`) or the file's raw bytes. `{:path, tmp_path}`
  is what a `Plug.Upload`/LiveView upload entry hands you; `{:binary,
  data}` is for in-memory content.
  """
  @type source :: {:path, Path.t()} | {:binary, binary()}

  @type opts :: keyword()

  @callback store(source, filename :: String.t(), content_type :: String.t(), opts) ::
              {:ok, key} | {:error, term()}

  @callback delete(key, opts) :: :ok | {:error, term()}

  @doc "Resolve a key to an on-disk (or backend-native) path. `:error` if the key is invalid (e.g. escapes the storage root)."
  @callback path(key, opts) :: {:ok, String.t()} | :error

  @callback open(key, opts) :: {:ok, File.io_device()} | {:error, term()}
end
