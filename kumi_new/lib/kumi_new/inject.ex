defmodule KumiNew.Inject do
  @moduledoc """
  Pure string-in/string-out edits applied to files `mix igniter.new`
  generates. No I/O here — callers read/write the files; these functions
  just transform content and fail loudly if their anchor isn't found
  exactly once (so a future igniter.new/phx.new format change breaks
  loudly instead of silently no-op'ing).
  """

  @deps_anchor "defp deps do\n    [\n"
  @port_anchor "  hostname: \"localhost\",\n"

  @doc """
  Inserts `{:kumi, path: ...}` (and `{:kumi_admin, path: ...}` unless
  `admin?` is false) as the first entries of the `deps do [...]` list in a
  generated mix.exs.
  """
  @spec insert_deps(String.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, String.t()}
  def insert_deps(mix_exs, kumi_path, admin?) do
    case count_occurrences(mix_exs, @deps_anchor) do
      1 ->
        kumi_dep = ~s[      {:kumi, path: #{inspect(Path.join(kumi_path, "kumi"))}},\n]

        admin_dep =
          if admin? do
            ~s[      {:kumi_admin, path: #{inspect(Path.join(kumi_path, "kumi_admin"))}},\n]
          else
            ""
          end

        {:ok,
         String.replace(mix_exs, @deps_anchor, @deps_anchor <> kumi_dep <> admin_dep,
           global: false
         )}

      0 ->
        {:error,
         "could not find `defp deps do [` in mix.exs — igniter.new's output format changed"}

      n ->
        {:error, "found #{n} occurrences of `defp deps do [` in mix.exs, expected exactly 1"}
    end
  end

  @doc """
  Inserts a `port: PORT,` line right after `hostname: "localhost",` in a
  generated dev.exs/test.exs Repo config block.
  """
  @spec patch_port(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def patch_port(config, port) do
    case count_occurrences(config, @port_anchor) do
      1 ->
        replacement = @port_anchor <> "  port: #{port},\n"
        {:ok, String.replace(config, @port_anchor, replacement, global: false)}

      0 ->
        {:error, "could not find `hostname: \"localhost\",` — config format changed"}

      n ->
        {:error, "found #{n} occurrences of `hostname: \"localhost\",`, expected exactly 1"}
    end
  end

  defp count_occurrences(content, anchor) do
    content
    |> String.split(anchor)
    |> length()
    |> Kernel.-(1)
  end
end
