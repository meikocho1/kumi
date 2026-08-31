defmodule KumiAdmin.Context do
  @moduledoc """
  Shared session/param resolution used by every KumiAdmin LiveView —
  reads back what `KumiAdmin.Router.kumi_admin/2` put in the LiveView
  session (`app`, `mount_path`, the actor function) and resolves the actor,
  the app's display text (`KumiAdmin.Text`, resolved once per mount rather
  than per render) and, when present, the `:resource` route param.
  """

  @type t :: %{
          app: module(),
          actor: term(),
          mount_path: String.t(),
          sign_out_path: String.t(),
          sign_in_path: String.t(),
          user_resource: module() | nil,
          register_path: String.t(),
          resource: module() | nil,
          text: KumiAdmin.Text.t()
        }

  @spec resolve(map(), map(), Phoenix.LiveView.Socket.t()) :: t()
  def resolve(session, params, socket) do
    app = Map.fetch!(session, "kumi_admin_app")
    mount_path = Map.fetch!(session, "kumi_admin_path")
    sign_out_path = Map.get(session, "kumi_admin_sign_out_path", "/sign-out")
    sign_in_path = Map.get(session, "kumi_admin_sign_in_path", "/sign-in")
    user_resource = Map.get(session, "kumi_admin_user_resource", nil)
    register_path = Map.get(session, "kumi_admin_register_path", "/register")
    actor = KumiAdmin.Actor.resolve(session["kumi_admin_actor"], socket)
    resource = params["resource"] && KumiAdmin.Slug.resolve(app, params["resource"])
    strings = Map.get(session, "kumi_admin_strings", %{})

    %{
      app: app,
      actor: actor,
      mount_path: mount_path,
      sign_out_path: sign_out_path,
      sign_in_path: sign_in_path,
      user_resource: user_resource,
      register_path: register_path,
      resource: resource,
      text: KumiAdmin.Text.new(app, strings)
    }
  end
end
