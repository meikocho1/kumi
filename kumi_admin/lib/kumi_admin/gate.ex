defmodule KumiAdmin.Gate do
  @moduledoc """
  Mount-time auth gate. Every KumiAdmin LiveView calls `check/2` right
  after `KumiAdmin.Context.resolve/3`, and returns early on `{:halt, _}`
  — KumiAdmin is a post-login experience, not a shell that renders an
  empty state for visitors (see `KumiAdmin.Router` moduledoc: KumiAdmin
  has no auth of its own, so this is routing UX, not authentication).

    * actor present → `{:cont, socket}`; policy-forbidden reads still
      render the existing honest empty states, unchanged.
    * actor `nil` and `:user_resource` configured and currently empty →
      redirect to `:register_path` ("create the first user" onboarding
      on a fresh install).
    * actor `nil` otherwise (including any count error) → redirect to
      `:sign_in_path`.

  The zero-users count runs with `authorize?: false` — deliberately: it
  is bootstrap-only logic that exposes a single boolean ("are there zero
  users"), never any user data, and only ever runs when there is no
  actor to authorize as in the first place.
  """

  alias KumiAdmin.Context

  @spec check(Context.t(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def check(%{actor: actor}, socket) when not is_nil(actor), do: {:cont, socket}

  def check(context, socket) do
    {:halt, Phoenix.LiveView.redirect(socket, to: redirect_path(context))}
  end

  @doc """
  The redirect target for an actor-less mount. Takes an optional
  `count_fn` (default: a real `Ash.count/2, authorize?: false`) so the
  decision is unit-testable without a database — pass a stub returning
  `{:ok, 0}` / `{:ok, n}` / `{:error, term()}`.
  """
  @spec redirect_path(Context.t(), (module() -> {:ok, non_neg_integer()} | {:error, term()})) ::
          String.t()
  def redirect_path(context, count_fn \\ &default_count/1)

  def redirect_path(%{user_resource: nil, sign_in_path: sign_in_path}, _count_fn),
    do: sign_in_path

  def redirect_path(
        %{user_resource: user_resource, register_path: register_path, sign_in_path: sign_in_path},
        count_fn
      ) do
    case count_fn.(user_resource) do
      {:ok, 0} -> register_path
      _ -> sign_in_path
    end
  end

  defp default_count(user_resource), do: Ash.count(user_resource, authorize?: false)
end
