defmodule KumiAdmin.ResourceShowLive do
  @moduledoc """
  Generic record detail: every public attribute, read-only, plus loaded
  `belongs_to` relationships rendered by a name-ish field when the related
  resource has one, else its id. Not found / no access renders honestly
  instead of crashing — same as `KumiAdmin.ResourceIndexLive`.
  """

  use Phoenix.LiveView

  alias KumiAdmin.Components.Shell

  def mount(params, session, socket) do
    context = KumiAdmin.Context.resolve(session, params, socket)

    socket =
      socket
      |> assign(app: context.app, mount_path: context.mount_path)
      |> assign(actor: context.actor, resource: context.resource)
      |> load_record(params["id"])

    {:ok, socket}
  end

  defp load_record(socket, id) do
    case socket.assigns.resource do
      nil ->
        assign(socket, error: :not_found, record: nil, attributes: [], relationships: [])

      resource ->
        relationships = belongs_to_relationships(resource)

        opts = [actor: socket.assigns.actor, load: Enum.map(relationships, & &1.name)]

        case Ash.get(resource, id, opts) do
          {:ok, record} ->
            attributes = Ash.Resource.Info.public_attributes(resource)
            assign(socket, error: nil, record: record, attributes: attributes, relationships: relationships)

          {:error, _reason} ->
            assign(socket, error: :forbidden, record: nil, attributes: [], relationships: [])
        end
    end
  end

  defp belongs_to_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(&(&1.type == :belongs_to))
  end

  defp relationship_display(nil), do: "—"

  defp relationship_display(related) do
    if Map.has_key?(related, :name) && related.name do
      related.name
    else
      KumiAdmin.Format.cell(:id, related.id)
    end
  end

  def render(assigns) do
    ~H"""
    <Shell.shell app={@app} mount_path={@mount_path} active_resource={@resource}>
      <a
        :if={@resource}
        href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@resource)}"}
        class="kumi-admin-back-link"
      >
        &larr; Back to {KumiAdmin.Label.plural(@resource)}
      </a>

      <p :if={@error == :not_found} class="kumi-admin-empty">
        Unknown resource.
      </p>

      <p :if={@error == :forbidden} class="kumi-admin-empty">
        No access or no record.
      </p>

      <div :if={is_nil(@error)}>
        <div :for={attribute <- @attributes} class="kumi-admin-field">
          <span class="kumi-admin-field-label">{Phoenix.Naming.humanize(attribute.name)}</span>
          <span class="kumi-admin-field-value">
            {KumiAdmin.Format.cell(attribute.name, Map.get(@record, attribute.name))}
          </span>
        </div>
        <div :for={relationship <- @relationships} class="kumi-admin-field">
          <span class="kumi-admin-field-label">{Phoenix.Naming.humanize(relationship.name)}</span>
          <span class="kumi-admin-field-value">
            {relationship_display(Map.get(@record, relationship.name))}
          </span>
        </div>
      </div>
    </Shell.shell>
    """
  end
end
