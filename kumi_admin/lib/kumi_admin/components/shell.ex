defmodule KumiAdmin.Components.Shell do
  @moduledoc """
  The product-shell chrome: sidebar (app title + navigation, driven
  entirely by `Kumi.App.Info`) wrapping whatever page content is given.
  Emits its own scoped `<style>` — no CSS framework dependency, so the
  shell looks right whether or not the host app ships Tailwind.
  """

  use Phoenix.Component

  alias Kumi.App.Info

  attr :app, :atom, required: true
  attr :mount_path, :string, required: true
  attr :active_resource, :atom, default: nil
  attr :actor, :any, default: nil
  attr :sign_out_path, :string, default: "/sign-out"
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(css()) %>
    </style>
    <div class="kumi-admin-shell">
      <nav class="kumi-admin-sidebar">
        <a href={@mount_path} class="kumi-admin-app-title">
          {Info.title(@app) || to_string(Info.name(@app))}
        </a>
        <ul class="kumi-admin-nav">
          <li :for={resource <- Info.navigation(@app)}>
            <a
              href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(resource)}"}
              class={[
                "kumi-admin-nav-link",
                resource == @active_resource && "kumi-admin-nav-active"
              ]}
            >
              {KumiAdmin.Label.plural(resource)}
            </a>
          </li>
        </ul>
      </nav>
      <div class="kumi-admin-main">
        <header class="kumi-admin-topbar">
          <span class="kumi-admin-topbar-title">
            {(@active_resource && KumiAdmin.Label.plural(@active_resource)) ||
              Info.title(@app) || to_string(Info.name(@app))}
          </span>
          <div :if={@actor} class="kumi-admin-topbar-user">
            <span :if={actor_email(@actor)} class="kumi-admin-topbar-email">
              {actor_email(@actor)}
            </span>
            <a href={@sign_out_path} class="kumi-admin-signout">Sign out</a>
          </div>
        </header>
        <main class="kumi-admin-content">
          <p :if={Phoenix.Flash.get(@flash, :info)} class="kumi-admin-flash kumi-admin-flash-info">
            {Phoenix.Flash.get(@flash, :info)}
          </p>
          <p :if={Phoenix.Flash.get(@flash, :error)} class="kumi-admin-flash kumi-admin-flash-error">
            {Phoenix.Flash.get(@flash, :error)}
          </p>
          {render_slot(@inner_block)}
          <footer class="kumi-admin-footer">
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
        </main>
      </div>
    </div>
    """
  end

  # Defensive: actor may lack an `:email` field entirely (Map.get simply
  # returns nil for a missing key, struct or not) — render nothing rather
  # than crash. `to_string/1` handles `Ash.CiString` transparently.
  defp actor_email(actor) when is_map(actor) do
    case Map.get(actor, :email) do
      nil -> nil
      email -> to_string(email)
    end
  end

  defp actor_email(_actor), do: nil

  @doc false
  def css do
    """
    .kumi-admin-shell {
      --kumi-bg: #f6f7f9;
      --kumi-surface: #fff;
      --kumi-border: #e4e7ec;
      --kumi-text: #101828;
      --kumi-text-muted: #667085;
      --kumi-accent: #4338CA;
      --kumi-accent-hover: #3730A3;
      --kumi-sidebar-bg: #101828;
      --kumi-sidebar-text: #d0d5dd;
      --kumi-sidebar-active-bg: #1d2939;
      --kumi-sidebar-active-text: #fff;
      --kumi-danger: #b42318;
      --kumi-radius: 8px;
      display: flex; min-height: 100vh; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
      font-size: 14px; color: var(--kumi-text); background: var(--kumi-bg);
    }
    .kumi-admin-sidebar { width: 220px; flex-shrink: 0; background: var(--kumi-sidebar-bg); padding: 1.25rem 1rem; }
    .kumi-admin-app-title { display: block; font-weight: 600; font-size: 1rem; margin-bottom: 1.5rem; text-decoration: none; color: #fff; }
    .kumi-admin-nav { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 2px; }
    .kumi-admin-nav-link { display: block; padding: 0.5rem 0.75rem; border-radius: var(--kumi-radius); text-decoration: none; color: var(--kumi-sidebar-text); font-size: 14px; border-left: 3px solid transparent; }
    .kumi-admin-nav-link:hover { background: var(--kumi-sidebar-active-bg); color: #fff; }
    .kumi-admin-nav-active { background: var(--kumi-sidebar-active-bg); color: var(--kumi-sidebar-active-text); font-weight: 600; border-left-color: var(--kumi-accent); }
    .kumi-admin-main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
    .kumi-admin-topbar { height: 56px; flex-shrink: 0; display: flex; align-items: center; justify-content: space-between; padding: 0 2rem; background: var(--kumi-surface); border-bottom: 1px solid var(--kumi-border); }
    .kumi-admin-topbar-title { font-weight: 600; font-size: 0.95rem; color: var(--kumi-text); }
    .kumi-admin-topbar-user { display: flex; align-items: center; gap: 1rem; }
    .kumi-admin-topbar-email { color: var(--kumi-text-muted); font-size: 0.85rem; }
    .kumi-admin-signout { color: var(--kumi-accent); text-decoration: none; font-size: 0.85rem; font-weight: 500; }
    .kumi-admin-signout:hover { color: var(--kumi-accent-hover); text-decoration: underline; }
    .kumi-admin-content { flex: 1; display: flex; flex-direction: column; padding: 1.5rem 2rem; }
    .kumi-admin-footer { margin-top: auto; padding-top: 1.5rem; display: flex; align-items: center; justify-content: flex-end; gap: 0.35rem; font-size: 12px; color: var(--kumi-text-muted); }
    .kumi-admin-title { font-size: 1.25rem; font-weight: 600; margin: 0 0 1rem; color: var(--kumi-text); }
    .kumi-admin-card { background: var(--kumi-surface); border: 1px solid var(--kumi-border); border-radius: var(--kumi-radius); padding: 1rem 1.25rem; margin-bottom: 1rem; max-width: 320px; }
    .kumi-admin-table { border-collapse: collapse; width: 100%; background: var(--kumi-surface); border: 1px solid var(--kumi-border); border-radius: var(--kumi-radius); overflow: hidden; }
    .kumi-admin-table th { text-align: left; padding: 0.6rem 0.9rem; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--kumi-text-muted); border-bottom: 1px solid var(--kumi-border); background: #fafbfc; }
    .kumi-admin-table td { text-align: left; padding: 0.65rem 0.9rem; border-bottom: 1px solid var(--kumi-border); }
    .kumi-admin-table tr:hover td { background: #fafbfc; }
    .kumi-admin-empty { color: var(--kumi-text-muted); font-style: normal; }
    .kumi-admin-pagination { margin-top: 1rem; display: flex; gap: 0.5rem; }
    .kumi-admin-field { margin-bottom: 0.9rem; }
    .kumi-admin-field-label { display: block; font-size: 12px; color: var(--kumi-text-muted); text-transform: uppercase; letter-spacing: 0.03em; margin-bottom: 0.25rem; }
    .kumi-admin-field-value { display: block; }
    .kumi-admin-back-link { display: inline-block; margin-bottom: 1rem; color: var(--kumi-text-muted); text-decoration: none; font-size: 0.9rem; }
    .kumi-admin-back-link:hover { color: var(--kumi-text); }
    .kumi-admin-actions { display: flex; align-items: center; justify-content: space-between; gap: 0.75rem; margin-bottom: 1rem; }
    .kumi-admin-actions .kumi-admin-title { margin: 0; }
    .kumi-admin-button { display: inline-block; padding: 0.5rem 1rem; border-radius: var(--kumi-radius); border: 1px solid var(--kumi-accent); background: var(--kumi-accent); color: #fff; text-decoration: none; font: inherit; font-weight: 500; cursor: pointer; }
    .kumi-admin-button:hover { background: var(--kumi-accent-hover); border-color: var(--kumi-accent-hover); }
    .kumi-admin-button-danger { background: var(--kumi-surface); color: var(--kumi-danger); border-color: var(--kumi-danger); }
    .kumi-admin-button-danger:hover { background: var(--kumi-danger); color: #fff; }
    .kumi-admin-search { margin-bottom: 1rem; }
    .kumi-admin-input { padding: 0.5rem 0.75rem; border: 1px solid var(--kumi-border); border-radius: var(--kumi-radius); font: inherit; width: 100%; max-width: 320px; box-sizing: border-box; background: var(--kumi-surface); color: var(--kumi-text); }
    .kumi-admin-input:focus { outline: none; border-color: var(--kumi-accent); box-shadow: 0 0 0 3px rgba(67, 56, 202, 0.15); }
    .kumi-admin-checkbox { width: auto; max-width: none; }
    .kumi-admin-field-error { color: var(--kumi-danger); font-size: 0.85rem; margin: 0.25rem 0 0; }
    .kumi-admin-flash { padding: 0.7rem 1rem; border-radius: var(--kumi-radius); margin-bottom: 1rem; font-size: 0.9rem; }
    .kumi-admin-flash-info { background: #ecfdf3; color: #05603a; }
    .kumi-admin-flash-error { background: #fef3f2; color: var(--kumi-danger); }
    .kumi-admin-panel { background: var(--kumi-surface); border: 1px solid var(--kumi-border); border-radius: var(--kumi-radius); margin-bottom: 1.25rem; }
    .kumi-admin-panel-header { padding: 0.85rem 1.25rem; border-bottom: 1px solid var(--kumi-border); }
    .kumi-admin-panel-body { padding: 1.25rem; }
    .kumi-admin-section-title { margin: 0; font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--kumi-text-muted); }
    .kumi-admin-attribute-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 1.5rem; }
    @media (max-width: 800px) { .kumi-admin-attribute-grid { grid-template-columns: 1fr; } }
    .kumi-admin-record-header { align-items: flex-start; margin-bottom: 1.5rem; }
    .kumi-admin-actions-heading { display: flex; flex-direction: column; gap: 0.15rem; }
    .kumi-admin-actions-buttons { display: flex; gap: 0.75rem; align-items: center; flex-shrink: 0; }
    .kumi-admin-subtitle { margin: 0; color: var(--kumi-text-muted); font-size: 0.85rem; }
    .kumi-admin-badge { display: inline-block; padding: 0.15rem 0.55rem; border-radius: 999px; background: #eef2ff; color: var(--kumi-accent); font-size: 0.75rem; font-weight: 500; text-transform: capitalize; }
    """
  end
end
