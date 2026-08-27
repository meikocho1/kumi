defmodule KumiAdmin.GateTest do
  @moduledoc """
  Unit tests for the redirect decision, without a database: `redirect_path/2`
  takes a `count_fn` so the zero-users branch is testable by injecting the
  count result directly, per `KumiAdmin.Gate`'s own doc.
  """

  use ExUnit.Case, async: true

  alias KumiAdmin.Gate

  defp context(overrides) do
    Map.merge(
      %{
        app: :whatever,
        mount_path: "/kumi-admin",
        sign_out_path: "/sign-out",
        sign_in_path: "/sign-in",
        user_resource: nil,
        register_path: "/register",
        resource: nil
      },
      overrides
    )
  end

  test "check/2 continues when an actor is present, regardless of user_resource" do
    assert {:cont, :socket} =
             Gate.check(context(%{actor: %{id: 1}, user_resource: SomeApp.User}), :socket)
  end

  test "redirect_path/2 goes to sign_in_path when no user_resource is configured" do
    assert Gate.redirect_path(context(%{user_resource: nil})) == "/sign-in"
  end

  test "redirect_path/2 goes to register_path when user_resource has zero records" do
    ctx = context(%{user_resource: SomeApp.User})
    assert Gate.redirect_path(ctx, fn SomeApp.User -> {:ok, 0} end) == "/register"
  end

  test "redirect_path/2 goes to sign_in_path when user_resource has records" do
    ctx = context(%{user_resource: SomeApp.User})
    assert Gate.redirect_path(ctx, fn SomeApp.User -> {:ok, 3} end) == "/sign-in"
  end

  test "redirect_path/2 falls back to sign_in_path on any count error (never crashes the gate)" do
    ctx = context(%{user_resource: SomeApp.User})
    assert Gate.redirect_path(ctx, fn SomeApp.User -> {:error, :boom} end) == "/sign-in"
  end

  test "check/2 halts with a redirected socket when actor is nil" do
    ctx = context(%{actor: nil, user_resource: nil})
    {:halt, socket} = Gate.check(ctx, %Phoenix.LiveView.Socket{})
    assert {:redirect, %{to: "/sign-in"}} = socket.redirected
  end
end
