defmodule KumiAdmin.Components.OrganismsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KumiAdmin.Components.Organisms
  alias KumiAdmin.Test.{Contact, Widget}

  # The English default: an app declaring no locale and no labels, so these
  # tests keep asserting the derived wording.
  @text KumiAdmin.Text.new(KumiAdmin.Test.App)

  test "record_header/1 renders the label, subtitle, and actions slot" do
    html =
      render_html(fn assigns ->
        ~H"""
        <Organisms.record_header label="Acme Corp" subtitle="Account · a1b2c3d4…">
          <:actions>
            <a href="/x/edit">Edit</a>
          </:actions>
        </Organisms.record_header>
        """
      end)

    assert html =~ ~s(<h1 class="kumi-admin-title">Acme Corp</h1>)
    assert html =~ ~s(<p class="kumi-admin-subtitle">Account · a1b2c3d4…</p>)
    assert html =~ "Edit"
  end

  test "attribute_panel/1 renders each attribute as a field, badging atom values" do
    attributes = Ash.Resource.Info.public_attributes(Widget)
    record = %Widget{a: "x", status: :published, active: true, description: nil}

    html =
      render_html(fn assigns ->
        assigns = assign(assigns, attributes: attributes, record: record, text: @text)

        ~H"""
        <Organisms.attribute_panel
          attributes={@attributes}
          record={@record}
          text={@text}
          resource={Widget}
        />
        """
      end)

    assert html =~ "Attributes"
    assert html =~ ~s(<span class="kumi-admin-field-label">A</span>)
    # atom, non-boolean, non-nil value renders as a badge
    assert html =~ ~s(<span class="kumi-admin-badge">published</span>)
    # boolean atom values are not badged
    refute html =~ ~s(<span class="kumi-admin-badge">true</span>)
    # nil renders through KumiAdmin.Format.cell's em-dash, not a badge
    assert html =~ "—"
  end

  describe "relation_panel/1" do
    test "renders nothing at all when there are no items" do
      html =
        render_html(fn assigns ->
          assigns = assign(assigns, :text, @text)

          ~H"""
          <Organisms.relation_panel items={[]} text={@text} />
          """
        end)

      assert String.trim(html) == ""
    end

    test "renders a link for {:link, url, text} and plain text for {:text, text}" do
      items = [
        %{label: "Avatar", display: {:link, "/uploads/a.png", "a1b2c3d4"}},
        %{label: "Account", display: {:text, "Acme Corp"}}
      ]

      html =
        render_html(fn assigns ->
          assigns = assigns |> assign(:items, items) |> assign(:text, @text)

          ~H"""
          <Organisms.relation_panel items={@items} text={@text} />
          """
        end)

      assert html =~ "Relations"
      assert html =~ ~s(<a href="/uploads/a.png">)
      assert html =~ "a1b2c3d4"
      assert html =~ "Acme Corp"
    end
  end

  describe "child_section/1" do
    defp base_section(overrides) do
      Map.merge(
        %{
          destination: Contact,
          columns: [:id, :name],
          foreign_keys: [],
          linkable?: true,
          rows: [],
          has_more?: false,
          error: nil
        },
        overrides
      )
    end

    test "forbidden section shows the honest 'No access.' message" do
      section = base_section(%{error: :forbidden})

      html =
        render_html(fn assigns ->
          assigns = assigns |> assign(:section, section) |> assign(:text, @text)

          ~H"""
          <Organisms.child_section section={@section} mount_path="/admin" text={@text} />
          """
        end)

      assert html =~ "No access."
      refute html =~ "kumi-admin-table"
    end

    test "empty section shows the non-committal 'No records visible to you.' (M4)" do
      # Not "No records yet." — a filter-based read policy (the default)
      # makes an unauthorized child load look identical to a genuinely
      # empty relationship, so the wording must not claim the table is
      # empty. See `KumiAdmin.ResourceIndexLive`'s matching fix.
      section = base_section(%{})

      html =
        render_html(fn assigns ->
          assigns = assigns |> assign(:section, section) |> assign(:text, @text)

          ~H"""
          <Organisms.child_section section={@section} mount_path="/admin" text={@text} />
          """
        end)

      assert html =~ "No records visible to you."
      refute html =~ "No records yet."
    end

    test "rows render as a table, id column linked when linkable?, and overflow footer when has_more?" do
      rows = [%{id: "row-1", name: "Ada"}]
      section = base_section(%{rows: rows, has_more?: true})

      html =
        render_html(fn assigns ->
          assigns = assigns |> assign(:section, section) |> assign(:text, @text)

          ~H"""
          <Organisms.child_section section={@section} mount_path="/admin" text={@text} />
          """
        end)

      assert html =~ "Contacts"
      assert html =~ ~s(<a href="/admin/contact/row-1">)
      assert html =~ "…and more."
    end

    test "id column is plain text (not linked) when linkable? is false" do
      rows = [%{id: "row-1", name: "Ada"}]
      section = base_section(%{rows: rows, linkable?: false})

      html =
        render_html(fn assigns ->
          assigns = assigns |> assign(:section, section) |> assign(:text, @text)

          ~H"""
          <Organisms.child_section section={@section} mount_path="/admin" text={@text} />
          """
        end)

      refute html =~ ~s(href="/admin/contact/row-1")
    end
  end

  defp render_html(fun) do
    render_component(fun, %{})
  end
end
