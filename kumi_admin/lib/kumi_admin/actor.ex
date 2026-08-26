defmodule KumiAdmin.Actor do
  @moduledoc """
  Resolves the Ash actor for KumiAdmin's own `Ash.read`/`Ash.get` calls.

  KumiAdmin does not authenticate anyone itself — it reads the actor back
  out of `socket.assigns` after the host's own `on_mount` hooks (passed to
  `KumiAdmin.Router.kumi_admin/2` via `on_mount:`) have already run and
  populated whatever assign they use (typically `:current_user`).

  Override the lookup with `actor: {Module, :function}` on `kumi_admin/2`
  — `function.(socket)` must return the actor (or `nil`).
  """

  @doc "Default lookup: `socket.assigns[:current_user]`."
  @spec from_current_user(Phoenix.LiveView.Socket.t()) :: term()
  def from_current_user(socket), do: socket.assigns[:current_user]

  @doc "Resolves an actor given the `{module, function}` configured on the router."
  @spec resolve({module(), atom()}, Phoenix.LiveView.Socket.t()) :: term()
  def resolve({module, function}, socket), do: apply(module, function, [socket])
end
