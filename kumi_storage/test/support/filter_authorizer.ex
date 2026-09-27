defmodule KumiStorage.Test.FilterAuthorizer do
  @moduledoc """
  Authorizes only rows with `byte_size <= actor.max_bytes`, by answering
  strict_check with that filter, as `Ash.Policy.Authorizer` answers for a
  policy like `authorize_if expr(owner_id == ^actor(:id))`. On a create
  Ash can only check such a filter against the inserted row, inside the
  transaction. Stands in for those policies because `Ash.Policy.Authorizer`
  needs a SAT solver, which kumi_storage doesn't depend on.
  """

  @behaviour Ash.Authorizer

  import Ash.Expr

  @impl true
  def initial_state(actor, _resource, _action, _domain), do: %{actor: actor}

  @impl true
  def strict_check_context(_state), do: []

  @impl true
  def strict_check(%{actor: %{max_bytes: max_bytes}} = state, _context),
    do: {:filter, state, expr(byte_size <= ^max_bytes)}

  def strict_check(state, _context), do: {:authorized, state}

  @impl true
  def check_context(_state), do: []

  @impl true
  def check(_state, _context), do: :authorized
end
