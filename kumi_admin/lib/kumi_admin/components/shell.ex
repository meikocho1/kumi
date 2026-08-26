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
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <style>{css()}</style>
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
      <main class="kumi-admin-content">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc false
  def css do
    """
    .kumi-admin-shell { display: flex; min-height: 100vh; font-family: system-ui, sans-serif; color: #1a1a1a; }
    .kumi-admin-sidebar { width: 220px; flex-shrink: 0; border-right: 1px solid #ddd; padding: 1rem; }
    .kumi-admin-app-title { display: block; font-weight: 600; font-size: 1.1rem; margin-bottom: 1rem; text-decoration: none; color: inherit; }
    .kumi-admin-nav { list-style: none; margin: 0; padding: 0; }
    .kumi-admin-nav-link { display: block; padding: 0.4rem 0.5rem; border-radius: 4px; text-decoration: none; color: #333; }
    .kumi-admin-nav-link:hover { background: #f0f0f0; }
    .kumi-admin-nav-active { background: #e6e6e6; font-weight: 600; }
    .kumi-admin-content { flex: 1; padding: 1.5rem 2rem; }
    .kumi-admin-title { font-size: 1.4rem; margin: 0 0 1rem; }
    .kumi-admin-card { border: 1px solid #ddd; border-radius: 6px; padding: 1rem; margin-bottom: 1rem; max-width: 320px; }
    .kumi-admin-table { border-collapse: collapse; width: 100%; }
    .kumi-admin-table th, .kumi-admin-table td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #eee; }
    .kumi-admin-empty { color: #666; font-style: italic; }
    .kumi-admin-pagination { margin-top: 1rem; display: flex; gap: 0.5rem; }
    .kumi-admin-field { margin-bottom: 0.75rem; }
    .kumi-admin-field-label { display: block; font-size: 0.8rem; color: #666; text-transform: uppercase; letter-spacing: 0.03em; }
    .kumi-admin-field-value { display: block; }
    .kumi-admin-back-link { display: inline-block; margin-bottom: 1rem; }
    """
  end
end
