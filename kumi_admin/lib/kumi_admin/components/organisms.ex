defmodule KumiAdmin.Components.Organisms do
  @moduledoc """
  Page-section-sized compositions for the record detail page: the header
  (record label + resource/id line + actions), the attribute grid, the
  belongs_to grid, and one has_many child section. Each takes data that's
  already been derived (attribute/relationship/section structs) — no Ash
  calls happen in here, only display decisions.
  """

  use Phoenix.Component

  alias KumiAdmin.Components.Atoms
  alias KumiAdmin.Components.Molecules

  attr :label, :string, required: true
  attr :subtitle, :string, required: true
  slot :actions

  def record_header(assigns) do
    ~H"""
    <Molecules.action_bar class="kumi-admin-record-header">
      <h1 class="kumi-admin-title">{@label}</h1>
      <p class="kumi-admin-subtitle">{@subtitle}</p>
      <:actions>{render_slot(@actions)}</:actions>
    </Molecules.action_bar>
    """
  end

  attr :attributes, :list, required: true
  attr :record, :any, required: true

  def attribute_panel(assigns) do
    ~H"""
    <Molecules.panel>
      <:header><Atoms.section_title text="Attributes" /></:header>
      <div class="kumi-admin-attribute-grid">
        <Molecules.field
          :for={attribute <- @attributes}
          label={Phoenix.Naming.humanize(attribute.name)}
        >
          <% value = Map.get(@record, attribute.name) %>
          <Atoms.badge
            :if={is_atom(value) and not is_nil(value) and not is_boolean(value)}
            text={KumiAdmin.Format.cell(attribute.name, value)}
          />
          <span :if={!(is_atom(value) and not is_nil(value) and not is_boolean(value))}>
            {KumiAdmin.Format.cell(attribute.name, value)}
          </span>
        </Molecules.field>
      </div>
    </Molecules.panel>
    """
  end

  attr :items, :list, required: true

  def relation_panel(assigns) do
    ~H"""
    <Molecules.panel :if={@items != []}>
      <:header><Atoms.section_title text="Relations" /></:header>
      <div class="kumi-admin-attribute-grid">
        <Molecules.field :for={item <- @items} label={item.label}>
          <a :if={match?({:link, _, _}, item.display)} href={elem(item.display, 1)}>
            {elem(item.display, 2)}
          </a>
          <span :if={match?({:text, _}, item.display)}>{elem(item.display, 1)}</span>
        </Molecules.field>
      </div>
    </Molecules.panel>
    """
  end

  attr :section, :map, required: true
  attr :mount_path, :string, required: true

  def child_section(assigns) do
    ~H"""
    <Molecules.panel>
      <:header><Atoms.section_title text={KumiAdmin.Label.plural(@section.destination)} /></:header>
      <Atoms.empty :if={@section.error == :forbidden} text="No access." />
      <%!-- Same non-committal wording as the top-level index page (M4): a
      filter-based read policy makes an unauthorized child load look
      identical to a genuinely empty relationship. --%>
      <Atoms.empty
        :if={@section.error == nil and @section.rows == []}
        text="No records visible to you."
      />
      <Molecules.data_table
        :if={@section.error == nil and @section.rows != []}
        columns={@section.columns}
        rows={@section.rows}
      >
        <:cell :let={%{column: column, row: row}}>
          <a
            :if={column == :id and @section.linkable?}
            href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@section.destination)}/#{row.id}"}
          >
            {KumiAdmin.Format.cell(column, Map.get(row, column))}
          </a>
          <span :if={column != :id or !@section.linkable?}>
            {KumiAdmin.Format.cell(column, Map.get(row, column))}
          </span>
        </:cell>
      </Molecules.data_table>
      <Atoms.empty :if={@section.error == nil and @section.has_more?} text="…and more." />
    </Molecules.panel>
    """
  end
end
