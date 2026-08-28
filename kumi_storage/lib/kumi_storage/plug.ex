defmodule KumiStorage.Plug do
  @moduledoc """
  Serves stored files by key: `GET <mount>/:key`. Plug-only — no Phoenix
  dependency (blueprint §6 point 7). `mix kumi_storage.install` forwards a
  host router path to this plug (or prints the snippet to add it by hand).

  Reads `:backend` and the backend's own opts (everything else under
  `config :kumi_storage, ...`) from Application config once per request —
  this plug IS the config-reading boundary; `KumiStorage.Backend.Local`
  itself never touches Application config (see its moduledoc).

  404s on a missing file OR a key that resolves outside the backend's
  root (`Backend.path/2` returns `:error` for those) — never lets
  `Plug.Conn.send_file/3` see a path a client shouldn't be able to reach.

  Every response (success and 404) carries `x-content-type-options:
  nosniff` — defence in depth against a browser second-guessing the
  Content-Type this plug sets, on top of `KumiStorage.Backend.Local`
  deriving the stored extension from the validated content type rather
  than the client-supplied filename.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    backend = Application.fetch_env!(:kumi_storage, :backend)
    backend_opts = Application.get_all_env(:kumi_storage) |> Keyword.delete(:backend)

    with [key] <- conn.path_info,
         {:ok, path} <- backend.path(key, backend_opts),
         true <- File.regular?(path) do
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> send_file(200, path)
    else
      _ ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> send_resp(404, "Not Found")
        |> halt()
    end
  end
end
