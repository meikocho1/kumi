defmodule KumiStorage.Test.BlockedActorAuthorizer do
  @moduledoc """
  Forbids every action for an actor with `role: :blocked` and authorizes
  everything else. Stands in for a host's policies: `Ash.Policy.Authorizer`
  needs a SAT solver, which kumi_storage doesn't depend on.
  """

  @behaviour Ash.Authorizer

  @impl true
  def initial_state(actor, _resource, _action, _domain), do: %{actor: actor}

  @impl true
  def strict_check_context(_state), do: []

  @impl true
  def strict_check(%{actor: %{role: :blocked}}, _context),
    do: {:error, Ash.Error.Forbidden.exception([])}

  def strict_check(state, _context), do: {:authorized, state}

  @impl true
  def check_context(_state), do: []

  @impl true
  def check(_state, _context), do: :authorized
end
