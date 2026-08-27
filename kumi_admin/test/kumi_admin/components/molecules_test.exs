defmodule KumiAdmin.Components.MoleculesTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KumiAdmin.Components.Molecules

  test "field/1 renders a label and its value slot" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Molecules.field label="Industry">Manufacturing</Molecules.field>
        """
      end)

    assert html =~ ~s(<span class="kumi-admin-field-label">Industry</span>)
    assert html =~ "Manufacturing"
  end

  describe "panel/1" do
    test "renders the header slot when given" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Molecules.panel>
            <:header>Attributes</:header>
            body-content
          </Molecules.panel>
          """
        end)

      assert html =~ ~s(class="kumi-admin-panel-header")
      assert html =~ "Attributes"
      assert html =~ "body-content"
    end

    test "omits the header wrapper entirely when no header slot is given" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Molecules.panel>just-body</Molecules.panel>
          """
        end)

      refute html =~ "kumi-admin-panel-header"
      assert html =~ "just-body"
    end
  end

  describe "action_bar/1" do
    test "renders the heading content and the actions slot when given" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Molecules.action_bar>
            <h1>Acme Corp</h1>
            <:actions>
              <button>Edit</button>
            </:actions>
          </Molecules.action_bar>
          """
        end)

      assert html =~ "Acme Corp"
      assert html =~ ~s(class="kumi-admin-actions-buttons")
      assert html =~ "Edit"
    end

    test "omits the actions wrapper when no actions slot is given" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Molecules.action_bar>heading-only</Molecules.action_bar>
          """
        end)

      refute html =~ "kumi-admin-actions-buttons"
    end
  end

  test "data_table/1 renders humanized column headers and rows via the cell slot" do
    rows = [%{id: 1, name: "Deal A"}, %{id: 2, name: "Deal B"}]

    html =
      render_html(fn assigns ->
        assigns = assign(assigns, :rows, rows)

        ~H"""
        <Molecules.data_table columns={[:id, :name]} rows={@rows}>
          <:cell :let={%{column: column, row: row}}>{Map.get(row, column)}</:cell>
        </Molecules.data_table>
        """
      end)

    assert html =~ ~s(class="kumi-admin-table")
    assert html =~ "<th>Id</th>"
    assert html =~ "<th>Name</th>"
    assert html =~ "Deal A"
    assert html =~ "Deal B"
  end

  defp render_html(fun) do
    render_component(fun, %{})
  end
end
