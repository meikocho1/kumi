defmodule KumiAdmin.Components.AtomsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KumiAdmin.Components.Atoms

  describe "button/1" do
    test "renders an <a> with the primary button class when href is given" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Atoms.button href="/x/1/edit">Edit</Atoms.button>
          """
        end)

      assert html =~ ~s(<a href="/x/1/edit" class="kumi-admin-button )
      assert html =~ "Edit"
    end

    test "renders a <button> (no href) and forwards phx-click/data-confirm via :rest" do
      html =
        render_html(fn assigns ->
          ~H"""
          <Atoms.button phx-click="delete" data-confirm="Are you sure?" variant="danger">
            Delete
          </Atoms.button>
          """
        end)

      assert html =~ "<button"
      refute html =~ "<a "
      assert html =~ ~s(phx-click="delete")
      assert html =~ ~s(data-confirm="Are you sure?")
      assert html =~ "kumi-admin-button-danger"
    end
  end

  test "badge/1 renders the given text inside the badge class" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Atoms.badge text="published" />
        """
      end)

    assert html =~ ~s(class="kumi-admin-badge")
    assert html =~ "published"
  end

  test "field_label/1 and field_value/1 wrap their slot in the shared field classes" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Atoms.field_label>Name</Atoms.field_label>
        <Atoms.field_value>Acme</Atoms.field_value>
        """
      end)

    assert html =~ ~s(<span class="kumi-admin-field-label">Name</span>)
    assert html =~ ~s(<span class="kumi-admin-field-value">Acme</span>)
  end

  test "empty/1 renders the message as a kumi-admin-empty paragraph" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Atoms.empty text="No records yet." />
        """
      end)

    assert html =~ ~s(<p class="kumi-admin-empty">No records yet.</p>)
  end

  test "section_title/1 renders an h2 with the section-title class" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Atoms.section_title text="Attributes" />
        """
      end)

    assert html =~ ~s(<h2 class="kumi-admin-section-title">Attributes</h2>)
  end

  test "back_link/1 renders an arrow, the href, and the slot label" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Atoms.back_link href="/admin/account">Back to Accounts</Atoms.back_link>
        """
      end)

    assert html =~ ~s(href="/admin/account")
    assert html =~ "&larr;"
    assert html =~ "Back to Accounts"
  end

  defp render_html(fun) do
    render_component(fun, %{})
  end
end
