defmodule KumiAdmin.Context do
  @moduledoc """
  Shared session/param resolution used by every KumiAdmin LiveView —
  reads back what `KumiAdmin.Router.kumi_admin/2` put in the LiveView
  session (`app`, `mount_path`, the actor function) and resolves the actor
  and (when present) the `:resource` route param.
  """

  @type t :: %{
          app: module(),
          actor: term(),
          mount_path: String.t(),
          resource: module() | nil
        }

  @spec resolve(map(), map(), Phoenix.LiveView.Socket.t()) :: t()
  def resolve(session, params, socket) do
    app = Map.fetch!(session, "kumi_admin_app")
    mount_path = Map.fetch!(session, "kumi_admin_path")
    actor = KumiAdmin.Actor.resolve(session["kumi_admin_actor"], socket)
    resource = params["resource"] && KumiAdmin.Slug.resolve(app, params["resource"])

    %{app: app, actor: actor, mount_path: mount_path, resource: resource}
  end
end
