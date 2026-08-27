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

  attr :columns, :list, required: true
  attr :rows, :list, required: true
  slot :cell, required: true

  def data_table(assigns) do
    ~H"""
    <table class="kumi-admin-table">
      <thead>
        <tr>
          <th :for={column <- @columns}>{Phoenix.Naming.humanize(column)}</th>
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
end
