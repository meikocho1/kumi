defmodule KumiAdmin.ResourceShowLive do
  @moduledoc """
  Generic record detail: every public attribute, read-only, plus loaded
  `belongs_to` relationships rendered by a name-ish field when the related
  resource has one, else its id. Not found / no access renders honestly
  instead of crashing — same as `KumiAdmin.ResourceIndexLive`.

  `has_many` relationships render as one child table per relationship
  ("this Account's Deals"), one level deep only — depth is intentionally
  capped at 1, and there is no export/API depth question yet since no API
  surface exists. Each section is loaded with its own `Ash.load/3` call,
  separate from the record's own `Ash.get/3` — mixing them into one `load:`
  would mean a single policy-forbidden child resource flips the *entire*
  page to the `:forbidden` state. Loading separately means one section can
  fail honestly ("No access") while the record and every other section
  still render.
  """

  use Phoenix.LiveView

  alias KumiAdmin.Components.Atoms
  alias KumiAdmin.Components.Organisms
  alias KumiAdmin.Components.Shell

  def mount(params, session, socket) do
    context = KumiAdmin.Context.resolve(session, params, socket)

    case KumiAdmin.Gate.check(context, socket) do
      {:halt, socket} ->
        {:ok, socket}

      {:cont, socket} ->
        socket =
          socket
          |> assign(
            app: context.app,
            mount_path: context.mount_path,
            sign_out_path: context.sign_out_path,
            text: context.text
          )
          |> assign(actor: context.actor, resource: context.resource)
          |> load_record(params["id"])

        {:ok, socket}
    end
  end

  # LiveView events come from the client, not from the rendered DOM — an
  # authenticated user can push "delete" over the socket while the page
  # is in its not-found/forbidden state (`record` is nil), even though
  # the Delete button isn't rendered there. Guard it rather than let
  # `Ash.destroy(nil, ...)` crash the process (L5).
  def handle_event("delete", _params, %{assigns: %{record: nil}} = socket) do
    {:noreply, put_flash(socket, :error, t(socket, :forbidden))}
  end

  def handle_event("delete", _params, socket) do
    case Ash.destroy(socket.assigns.record, actor: socket.assigns.actor) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, t(socket, :deleted))
         |> push_navigate(
           to:
             "#{socket.assigns.mount_path}/#{KumiAdmin.Slug.for_resource(socket.assigns.resource)}"
         )}

      {:ok, _record} ->
        {:noreply,
         socket
         |> put_flash(:info, t(socket, :deleted))
         |> push_navigate(
           to:
             "#{socket.assigns.mount_path}/#{KumiAdmin.Slug.for_resource(socket.assigns.resource)}"
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, t(socket, :forbidden))}
    end
  end

  defp load_record(socket, id) do
    case socket.assigns.resource do
      nil ->
        assign(socket,
          error: :not_found,
          record: nil,
          attributes: [],
          relationships: [],
          has_many_sections: [],
          foreign_keys: [],
          can_update?: false,
          can_destroy?: false
        )

      resource ->
        relationships = belongs_to_relationships(resource)

        opts = [actor: socket.assigns.actor, load: Enum.map(relationships, & &1.name)]

        case Ash.get(resource, id, opts) do
          {:ok, record} ->
            attributes = KumiAdmin.Attributes.visible(resource)
            related_limit = Kumi.App.Info.related_limit(socket.assigns.app)
            admin_resources = Kumi.App.Info.resources(socket.assigns.app)

            has_many_sections =
              resource
              |> has_many_relationships()
              |> Enum.map(
                &load_has_many_section(
                  record,
                  &1,
                  related_limit,
                  admin_resources,
                  socket.assigns.actor
                )
              )

            assign(socket,
              error: nil,
              record: record,
              attributes: attributes,
              foreign_keys: KumiAdmin.Attributes.foreign_keys(resource),
              relationships: relationships,
              has_many_sections: has_many_sections,
              can_update?: KumiAdmin.Capability.can_update?(record, socket.assigns.actor),
              can_destroy?: KumiAdmin.Capability.can_destroy?(record, socket.assigns.actor)
            )

          # A record hidden by a filter-based read policy (the default)
          # never raises Forbidden — Ash reports it the same way as a
          # genuinely missing id: `Ash.Error.Invalid` wrapping
          # `Ash.Error.Query.NotFound` (see `Ash.get/3`). Folding that
          # into the same honest state as a real policy Forbidden is
          # deliberate, not a gap: telling the two apart would let a user
          # probe which ids exist. Anything else is a genuine bug (e.g. a
          # bad query) and must not be reported as "No access" (M3/M4).
          {:error, %Ash.Error.Forbidden{}} ->
            forbidden_record_state(socket)

          {:error, %Ash.Error.Invalid{errors: errors} = error} ->
            if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
              forbidden_record_state(socket)
            else
              raise error
            end

          {:error, error} ->
            raise error
        end
    end
  end

  defp t(socket, key), do: KumiAdmin.Text.string(socket.assigns.text, key)

  defp forbidden_record_state(socket) do
    assign(socket,
      error: :forbidden,
      record: nil,
      attributes: [],
      foreign_keys: [],
      relationships: [],
      has_many_sections: [],
      can_update?: false,
      can_destroy?: false
    )
  end

  defp belongs_to_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(&(&1.type == :belongs_to))
  end

  defp has_many_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(&(&1.type == :has_many))
  end

  # One child section per has_many, loaded independently of the parent
  # `Ash.get` (see moduledoc). `related_limit + 1` rows are fetched so we
  # can tell whether to show an "and more" line without a separate
  # `Ash.count` — ponytail: no exact total, just a boolean overflow flag.
  defp load_has_many_section(record, relationship, related_limit, admin_resources, actor) do
    child_query =
      relationship.destination
      |> Ash.Query.sort(:id)
      |> Ash.Query.limit(related_limit + 1)

    result = Ash.load(record, [{relationship.name, child_query}], actor: actor)
    build_has_many_section(relationship, admin_resources, related_limit, result)
  end

  # Split out from `load_has_many_section/5` so the section-building logic
  # (including the forbidden-child branch) is unit-testable by injecting a
  # prepared `{:ok, _} | {:error, _}` load result, without needing a real
  # policy-forbidden Ash resource in the test fixtures.
  @doc false
  def build_has_many_section(relationship, admin_resources, related_limit, load_result) do
    destination = relationship.destination

    base = %{
      relationship: relationship,
      destination: destination,
      # The child's FK back to this record is the same value on every row —
      # it carries no information on the parent's own page.
      columns:
        KumiAdmin.Columns.for_resource(destination) -- [relationship.destination_attribute],
      foreign_keys: KumiAdmin.Attributes.foreign_keys(destination),
      linkable?: destination in admin_resources
    }

    case load_result do
      {:ok, loaded} ->
        all_rows = Map.get(loaded, relationship.name)

        Map.merge(base, %{
          rows: Enum.take(all_rows, related_limit),
          has_more?: length(all_rows) > related_limit,
          error: nil
        })

      # Unlike a single-record `Ash.get`, a has_many load can't 404 — a
      # filter-based policy just yields an empty list, never an error. A
      # real error here is either a genuine policy Forbidden or a bug;
      # only the former is an honest "No access" (M3).
      {:error, %Ash.Error.Forbidden{}} ->
        Map.merge(base, %{rows: [], has_more?: false, error: :forbidden})

      {:error, error} ->
        raise error
    end
  end

  defp relationship_display(nil, _relationship), do: "—"

  defp relationship_display(related, relationship) do
    destination = relationship.destination

    if Code.ensure_loaded?(destination) and
         function_exported?(destination, :__kumi_attachment_url__, 1) do
      {:link, destination.__kumi_attachment_url__(related),
       KumiAdmin.Format.record_label(related)}
    else
      {:text, KumiAdmin.Format.record_label(related)}
    end
  end

  # "Account · a1b2c3d4…" — the muted second line under the record label on
  # the header. Raw last module segment, not `Phoenix.Naming.humanize/1`:
  # that function only splits on underscores, so it would mangle a
  # multi-word resource name like `StageCount` into "Stagecount".
  defp resource_subtitle(resource, record) do
    name = resource |> Module.split() |> List.last()
    "#{name} · #{KumiAdmin.Format.truncate_id(record.id)}"
  end

  defp relation_items(text, resource, relationships, record) do
    Enum.map(relationships, fn relationship ->
      %{
        label: KumiAdmin.Text.field(text, resource, relationship.name),
        display: relationship_display(Map.get(record, relationship.name), relationship)
      }
    end)
  end

  def render(assigns) do
    ~H"""
    <Shell.shell
      app={@app}
      text={@text}
      mount_path={@mount_path}
      active_resource={@resource}
      actor={@actor}
      sign_out_path={@sign_out_path}
      flash={@flash}
    >
      <Atoms.back_link
        :if={@resource}
        href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@resource)}"}
      >
        {KumiAdmin.Text.string(@text, :back_to, name: KumiAdmin.Text.resource(@text, @resource))}
      </Atoms.back_link>

      <Atoms.empty
        :if={@error == :not_found}
        text={KumiAdmin.Text.string(@text, :unknown_resource)}
      />
      <Atoms.empty
        :if={@error == :forbidden}
        text={KumiAdmin.Text.string(@text, :no_access_or_record)}
      />

      <div :if={is_nil(@error)}>
        <Organisms.record_header
          label={KumiAdmin.Format.record_label(@record)}
          subtitle={resource_subtitle(@resource, @record)}
        >
          <:actions>
            <Atoms.button
              :if={@can_update?}
              href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@resource)}/#{@record.id}/edit"}
            >
              {KumiAdmin.Text.string(@text, :edit)}
            </Atoms.button>
            <Atoms.button
              :if={@can_destroy?}
              variant="danger"
              phx-click="delete"
              data-confirm={KumiAdmin.Text.string(@text, :confirm_delete)}
            >
              {KumiAdmin.Text.string(@text, :delete)}
            </Atoms.button>
          </:actions>
        </Organisms.record_header>

        <Organisms.attribute_panel
          attributes={@attributes}
          record={@record}
          foreign_keys={@foreign_keys}
          text={@text}
          resource={@resource}
        />

        <Organisms.relation_panel
          items={relation_items(@text, @resource, @relationships, @record)}
          text={@text}
        />

        <Organisms.child_section
          :for={section <- @has_many_sections}
          section={section}
          mount_path={@mount_path}
          text={@text}
        />
      </div>
    </Shell.shell>
    """
  end
end
