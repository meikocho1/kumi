defmodule KumiAdmin.Components.Molecules do
  @moduledoc """
  Small compositions of atoms: a label+value pair, a card-like panel, a
  title/actions bar, and a generic table with caller-controlled cells.
  """

  use Phoenix.Component

  alias KumiAdmin.Components.Atoms

  attr :label, :string, required: true
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <div class="kumi-admin-field">
      <Atoms.field_label>{@label}</Atoms.field_label>
      <Atoms.field_value>{render_slot(@inner_block)}</Atoms.field_value>
    </div>
    """
  end

  attr :class, :any, default: nil
  slot :header
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={["kumi-admin-panel", @class]}>
      <header :if={@header != []} class="kumi-admin-panel-header">{render_slot(@header)}</header>
      <div class="kumi-admin-panel-body">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :actions

  def action_bar(assigns) do
    ~H"""
    <div class={["kumi-admin-actions", @class]}>
      <div class="kumi-admin-actions-heading">{render_slot(@inner_block)}</div>
      <div :if={@actions != []} class="kumi-admin-actions-buttons">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true

  @doc """
  A titled grid of `{label, value}` pairs — the dashboard's shape.

  Both halves arrive display-ready: the caller has already resolved the
  labels through `KumiAdmin.Text` and formatted the values (including the
  `"—"` a policy-forbidden read renders). This component only lays them
  out, so a metric and a workflow stage look the same on the page because
  they *are* the same thing here.
  """
  def stat_grid(assigns) do
    ~H"""
    <section class="kumi-admin-stats">
      <Atoms.section_title text={@title} />
      <div class="kumi-admin-stat-grid">
        <Atoms.stat :for={{label, value} <- @rows} label={label} value={value} />
      </div>
    </section>
    """
  end

  attr :columns, :list, required: true
  attr :rows, :list, required: true
  attr :headers, :list, default: nil
  slot :cell, required: true

  def data_table(assigns) do
    ~H"""
    <table class="kumi-admin-table">
      <thead>
        <tr>
          <th :for={header <- headers(assigns)}>{header}</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td :for={column <- @columns}>{render_slot(@cell, %{column: column, row: row})}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  # `headers` overrides the derived column names — that's where a
  # `Kumi.App` label lands. Without it the columns humanize themselves, so
  # a caller with no app in hand still renders sensible English.
  defp headers(%{headers: nil, columns: columns}),
    do: Enum.map(columns, &Phoenix.Naming.humanize/1)

  defp headers(%{headers: headers}), do: headers
end
