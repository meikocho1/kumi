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
  `admin?` is false, and a path dep for each selected optional module) as
  the first entries of the `deps do [...]` list in a generated mix.exs.
  `modules` is a list of `KumiNew.Modules` catalog keys (e.g. `[:storage]`);
  each resolves to a sibling directory of `kumi_path` (`kumi_storage/`).
  """
  @spec insert_deps(String.t(), String.t(), boolean(), [atom()]) ::
          {:ok, String.t()} | {:error, String.t()}
  def insert_deps(mix_exs, kumi_path, admin?, modules \\ []) do
    case count_occurrences(mix_exs, @deps_anchor) do
      1 ->
        kumi_dep = ~s[      {:kumi, path: #{inspect(Path.join(kumi_path, "kumi"))}},\n]

        admin_dep =
          if admin? do
            ~s[      {:kumi_admin, path: #{inspect(Path.join(kumi_path, "kumi_admin"))}},\n]
          else
            ""
          end

        module_deps =
          Enum.map_join(modules, "", fn key ->
            entry = KumiNew.Modules.fetch(key)

            ~s[      {#{inspect(entry.dep)}, path: #{inspect(Path.join(kumi_path, to_string(entry.dep)))}},\n]
          end)

        {:ok,
         String.replace(
           mix_exs,
           @deps_anchor,
           @deps_anchor <> kumi_dep <> admin_dep <> module_deps,
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

  @doc """
  Full replacement content for `page_html/home.html.heex` — same branded
  layout as the spike0_crm slice (header with app title + sign-in link,
  centered hero, muted footer with the Kumi mark), matching the kumi_admin
  shell's design tokens. Overwrites phx.new's default marketing page
  outright rather than patching it — there's no stable anchor worth
  targeting in that template.

  `admin?` mirrors `KumiNew.Args.t/0`'s `:admin?` — with `--no-admin` there
  is no `/kumi-admin` to link to, so the hero drops that button and "Sign
  in" becomes the (only, solid) call to action instead of silently linking
  to a route that 404s.
  """
  @spec home_page(String.t(), boolean()) :: String.t()
  def home_page(title, admin?) do
    actions =
      if admin? do
        """
              <a href="/kumi-admin" class="kumi-top-button kumi-top-button-primary">Open admin</a>
              <a href="/sign-in" class="kumi-top-button kumi-top-button-outline">Sign in</a>
        """
      else
        """
              <a href="/sign-in" class="kumi-top-button kumi-top-button-primary">Sign in</a>
        """
      end

    """
    <Layouts.flash_group flash={@flash} />
    <style>
      .kumi-top {
        min-height: 100vh; display: flex; flex-direction: column;
        background: #f6f7f9; color: #101828;
        font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
      }
      .kumi-top-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 2rem; }
      .kumi-top-brand { font-weight: 600; font-size: 1rem; color: #101828; text-decoration: none; }
      .kumi-top-signin { color: #4338CA; text-decoration: none; font-size: 0.9rem; font-weight: 500; }
      .kumi-top-signin:hover { color: #3730A3; text-decoration: underline; }
      .kumi-top-hero { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 2rem; }
      .kumi-top-title { font-size: 2rem; font-weight: 700; margin: 0 0 0.5rem; }
      .kumi-top-subtitle { color: #667085; font-size: 1rem; margin: 0 0 2rem; max-width: 32rem; }
      .kumi-top-actions { display: flex; gap: 0.75rem; }
      .kumi-top-button { padding: 0.6rem 1.4rem; border-radius: 8px; text-decoration: none; font-weight: 500; font-size: 0.95rem; }
      .kumi-top-button-primary { background: #4338CA; color: #fff; border: 1px solid #4338CA; }
      .kumi-top-button-primary:hover { background: #3730A3; border-color: #3730A3; }
      .kumi-top-button-outline { background: #fff; color: #101828; border: 1px solid #e4e7ec; }
      .kumi-top-button-outline:hover { border-color: #4338CA; color: #4338CA; }
      .kumi-top-footer { display: flex; align-items: center; justify-content: center; gap: 0.35rem; padding: 1.5rem; font-size: 12px; color: #667085; }
    </style>
    <div class="kumi-top">
      <header class="kumi-top-header">
        <a href="/" class="kumi-top-brand">#{title}</a>
        <a href="/sign-in" class="kumi-top-signin">Sign in</a>
      </header>
      <div class="kumi-top-hero">
        <h1 class="kumi-top-title">#{title}</h1>
        <p class="kumi-top-subtitle">Built with Kumi.</p>
        <div class="kumi-top-actions">
    #{actions}    </div>
      </div>
      <footer class="kumi-top-footer">
        <svg width="14" height="14" viewBox="0 0 100 100" role="img" aria-label="Kumi">
          <g fill="#4338CA" transform="rotate(45 50 50)">
            <rect x="16" y="16" width="20" height="20" rx="2" />
            <rect x="40" y="16" width="20" height="20" rx="2" />
            <rect x="64" y="16" width="20" height="20" rx="2" />
            <rect x="16" y="40" width="20" height="20" rx="2" />
            <rect x="64" y="40" width="20" height="20" rx="2" />
            <rect x="16" y="64" width="20" height="20" rx="2" />
            <rect x="40" y="64" width="20" height="20" rx="2" />
            <rect x="64" y="64" width="20" height="20" rx="2" />
          </g>
        </svg>
        Powered by Kumi
      </footer>
    </div>
    """
  end

  # Base64 data URI of design/kumi-logo.svg (mark only, comment stripped —
  # see BRAND.md). Shared verbatim by `auth_overrides/2` below and by
  # spike0_crm's hand-written `Spike0CrmWeb.AuthOverrides`.
  @kumi_mark_data_uri "data:image/svg+xml;base64," <>
                        "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgMTAwIiByb2xlPSJpbWciIGFyaWEtbGFiZWw9Ikt1bWkiPjxnIGZpbGw9IiM0MzM4Q0EiIHRyYW5zZm9ybT0icm90YXRlKDQ1IDUwIDUwKSI+PHJlY3QgeD0iMTYiIHk9IjE2IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iNDAiIHk9IjE2IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iNjQiIHk9IjE2IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iMTYiIHk9IjQwIiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iNjQiIHk9IjQwIiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iMTYiIHk9IjY0IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iNDAiIHk9IjY0IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PHJlY3QgeD0iNjQiIHk9IjY0IiB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHJ4PSIyIi8+PC9nPjwvc3ZnPg=="

  @doc """
  Full replacement content for the host's `<AppWeb>.AuthOverrides` module
  (an empty stub generated by ash_authentication_phoenix's own installer,
  already wired into every auth route's `overrides:` list — nothing to
  register here, only to fill in). Restyles the sign-in page to the same
  design tokens: Kumi mark + app title banner, white card, accent
  inputs/button. No footer override — `AshAuthentication.Phoenix.Overrides`
  exposes no slot for one on the sign-in page.
  """
  @spec auth_overrides(String.t(), String.t()) :: String.t()
  def auth_overrides(web_module, title) do
    """
    defmodule #{web_module}.AuthOverrides do
      @moduledoc \"\"\"
      Restyles ash_authentication_phoenix's sign-in page to the shared Kumi
      design tokens (see kumi_admin's shell CSS for the source of truth).
      Kumi-branded by default (see design/BRAND.md) — override
      `Components.Banner`'s `:image_url` yourself to drop the mark.
      \"\"\"

      use AshAuthentication.Phoenix.Overrides

      alias AshAuthentication.Phoenix.{Components, SignInLive, SignOutLive}

      @page_bg "min-h-screen grid place-items-center bg-[#f6f7f9]"
      @input_class "input input-bordered w-full focus:border-[#4338CA] focus:outline-none"
      @kumi_mark "#{@kumi_mark_data_uri}"

      override SignInLive do
        set :root_class, @page_bg
      end

      override SignOutLive do
        set :root_class, @page_bg
      end

      override Components.Banner do
        set :root_class, "w-full flex flex-col items-center justify-center gap-2 py-2"
        set :image_url, @kumi_mark
        set :image_class, "h-9 w-9"
        set :dark_image_url, nil
        set :text, "#{title}"
        set :text_class, "text-center text-lg font-semibold text-[#101828]"
        set :href_url, "/"
      end

      override Components.SignIn do
        set :root_class, "flex flex-col justify-center py-12 px-4 sm:px-6 lg:px-8"

        set :strategy_class, \"\"\"
        mx-auto w-full max-w-sm bg-white border border-[#e4e7ec] rounded-lg
        p-6 shadow-sm
        \"\"\"
      end

      override Components.Password do
        set :toggler_class, "flex-none text-[#4338CA] hover:text-[#3730A3] px-2 first:pl-0 last:pr-0"
      end

      override Components.Password.Input do
        set :input_class, @input_class
        set :input_class_with_error, @input_class <> " input-error"

        set :submit_class,
            "w-full mt-4 mb-4 rounded-md bg-[#4338CA] hover:bg-[#3730A3] text-white border-none"
      end
    end
    """
  end

  @doc """
  Full replacement content for `page_controller_test.exs`. `home_page/2`
  overwrites phx.new's default marketing page outright, which leaves
  phx.new's own generated test asserting copy that no longer exists
  ("Peace of mind from prototype to production") — a false failure on every
  fresh `mix kumi.new` app, not a signal about the app. Asserts "Built with
  Kumi." instead, which `home_page/2` renders unconditionally (`admin?`
  only changes the action buttons, never the subtitle).
  """
  @spec page_controller_test(String.t()) :: String.t()
  def page_controller_test(web_module) do
    """
    defmodule #{web_module}.PageControllerTest do
      use #{web_module}.ConnCase

      test "GET /", %{conn: conn} do
        conn = get(conn, ~p"/")
        assert html_response(conn, 200) =~ "Built with Kumi."
      end
    end
    """
  end
end
