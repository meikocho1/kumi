defmodule KumiAdmin.ContextTest do
  @moduledoc """
  `KumiAdmin.Context.resolve/3` reads the LiveView session
  `KumiAdmin.Router.kumi_admin/2` populates, resolves the actor via
  `KumiAdmin.Actor`, and resolves the `:resource` route param via
  `KumiAdmin.Slug`. `KumiAdmin.Test.App` (test/support/fixtures.ex) already
  declares `KumiAdmin.Test.Account`/`KumiAdmin.Test.Contact` as navigable
  resources, so it's reused here for the slug-resolution assertions.
  """

  use ExUnit.Case, async: true

  alias KumiAdmin.Context
  alias KumiAdmin.Test.{Account, App, Contact}

  defp session(overrides \\ %{}) do
    Map.merge(
      %{
        "kumi_admin_app" => App,
        "kumi_admin_path" => "/admin",
        "kumi_admin_actor" => {KumiAdmin.Actor, :from_current_user}
      },
      overrides
    )
  end

  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  defmodule CustomActorFn do
    @moduledoc false
    def pick(socket), do: socket.assigns[:impersonated_as]
  end

  test "resolves every optional session key when present, instead of falling back to defaults" do
    ctx =
      Context.resolve(
        session(%{
          "kumi_admin_sign_out_path" => "/custom-sign-out",
          "kumi_admin_sign_in_path" => "/custom-sign-in",
          "kumi_admin_user_resource" => KumiAdmin.Test.Widget,
          "kumi_admin_register_path" => "/custom-register"
        }),
        %{},
        socket()
      )

    assert ctx.sign_out_path == "/custom-sign-out"
    assert ctx.sign_in_path == "/custom-sign-in"
    assert ctx.user_resource == KumiAdmin.Test.Widget
    assert ctx.register_path == "/custom-register"
  end

  test "falls back to the documented defaults when the optional session keys are absent" do
    ctx = Context.resolve(session(), %{}, socket())

    assert ctx.sign_out_path == "/sign-out"
    assert ctx.sign_in_path == "/sign-in"
    assert ctx.user_resource == nil
    assert ctx.register_path == "/register"
  end

  test "raises when a required session key (app, mount_path) is missing" do
    incomplete = Map.delete(session(), "kumi_admin_app")
    assert_raise KeyError, fn -> Context.resolve(incomplete, %{}, socket()) end
  end

  test "resource param resolves to the matching app resource via KumiAdmin.Slug" do
    ctx = Context.resolve(session(), %{"resource" => "account"}, socket())
    assert ctx.resource == Account

    ctx2 = Context.resolve(session(), %{"resource" => "contact"}, socket())
    assert ctx2.resource == Contact
  end

  test "resource is nil when the :resource param is absent" do
    ctx = Context.resolve(session(), %{}, socket())
    assert ctx.resource == nil
  end

  test "resource is nil when the :resource param doesn't match any declared resource" do
    ctx = Context.resolve(session(), %{"resource" => "no_such_resource"}, socket())
    assert ctx.resource == nil
  end

  test "actor is resolved by calling through to the configured {module, function} against the socket" do
    # Default actor function reads `socket.assigns[:current_user]` — this is
    # the assertion that fails if actor resolution were ever replaced by a
    # hardcoded value instead of actually dispatching through the socket.
    user = %{id: 1, email: "person@example.com"}
    ctx = Context.resolve(session(), %{}, socket(%{current_user: user}))
    assert ctx.actor == user

    ctx_no_user = Context.resolve(session(), %{}, socket(%{}))
    assert ctx_no_user.actor == nil
  end

  test "actor resolution honors a custom {module, function} override, not just the default" do
    ctx =
      Context.resolve(
        session(%{"kumi_admin_actor" => {CustomActorFn, :pick}}),
        %{},
        socket(%{impersonated_as: :the_override, current_user: :ignored})
      )

    assert ctx.actor == :the_override
  end
end
