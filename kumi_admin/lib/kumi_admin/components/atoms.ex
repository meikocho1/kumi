defmodule KumiAdmin.Components.Atoms do
  @moduledoc """
  Smallest presentational pieces for the record detail page. No data
  derivation here — every attr is already display-ready by the time it
  reaches these.
  """

  use Phoenix.Component

  attr :variant, :string, default: "primary", values: ["primary", "danger"]
  attr :href, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      class={["kumi-admin-button", @variant == "danger" && "kumi-admin-button-danger"]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </a>
    <button
      :if={!@href}
      class={["kumi-admin-button", @variant == "danger" && "kumi-admin-button-danger"]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :text, :string, required: true

  def badge(assigns) do
    ~H"""
    <span class="kumi-admin-badge">{@text}</span>
    """
  end

  slot :inner_block, required: true

  def field_label(assigns) do
    ~H"""
    <span class="kumi-admin-field-label">{render_slot(@inner_block)}</span>
    """
  end

  slot :inner_block, required: true

  def field_value(assigns) do
    ~H"""
    <span class="kumi-admin-field-value">{render_slot(@inner_block)}</span>
    """
  end

  attr :text, :string, required: true

  def empty(assigns) do
    ~H"""
    <p class="kumi-admin-empty">{@text}</p>
    """
  end

  attr :text, :string, required: true

  def section_title(assigns) do
    ~H"""
    <h2 class="kumi-admin-section-title">{@text}</h2>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  def back_link(assigns) do
    ~H"""
    <a href={@href} class="kumi-admin-back-link">&larr; {render_slot(@inner_block)}</a>
    """
  end
end
