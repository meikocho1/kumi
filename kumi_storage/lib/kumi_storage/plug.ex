defmodule KumiStorage.Plug do
  @moduledoc """
  Serves stored files by key: `GET <mount>/:key`. Plug-only — no Phoenix
  dependency (blueprint §6 point 7). `mix kumi_storage.install` forwards a
  host router path to this plug (or prints the snippet to add it by hand):

      forward "/uploads", KumiStorage.Plug,
        config: {MyApp.Core.Attachment, :__kumi_storage_config__}

  `config: {module, function}` names a zero-arity function returning
  `{backend, backend_opts}`. The plug calls it on every request, so config
  set at runtime (e.g. `config/runtime.exs`) applies even though Phoenix
  runs `init/1` at compile time. The generated Attachment's
  `__kumi_storage_config__/0` is host code, so it may read
  `config :kumi_storage, ...`; this plug never reads Application config
  itself.

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
  def init(opts) do
    case Keyword.fetch(opts, :config) do
      {:ok, {module, function} = config} when is_atom(module) and is_atom(function) ->
        config

      _ ->
        raise ArgumentError, """
        KumiStorage.Plug needs `config: {module, function}`, a zero-arity \
        function returning {backend, backend_opts}. mix kumi_storage.install \
        generates one on your Attachment resource:

            forward "/uploads", KumiStorage.Plug,
              config: {MyApp.Core.Attachment, :__kumi_storage_config__}

        got: #{inspect(opts)}
        """
    end
  end

  @impl true
  def call(conn, {module, function}) do
    {backend, backend_opts} = apply(module, function, [])

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
