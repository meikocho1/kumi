defmodule KumiAdmin.CapabilityTest do
  @moduledoc """
  `KumiAdmin.Capability` gates New/Edit/Delete button visibility. Real Ash
  resources (in-memory `Ash.DataLayer.Ets`) with real
  `Ash.Policy.Authorizer` policies are used here rather than injecting a
  prepared result, because `can_create?/2`/`can_update?/2`/`can_destroy?/2`
  call `Ash.can?/3` directly with no injectable seam — testing the
  fail-open `rescue` genuinely requires `Ash.can?/3` to actually raise.
  """

  use ExUnit.Case, async: true

  alias KumiAdmin.Capability

  # A custom check whose `match?/3` reflects the actor's `:role` — used to
  # prove `can_*?` actually passes `Ash.can?/3`'s real answer through,
  # rather than only ever returning the fail-open default.
  defmodule RoleCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck
    def describe(_opts), do: "actor has :admin role"
    def match?(%{role: :admin}, _context, _opts), do: true
    def match?(_actor, _context, _opts), do: false
  end

  # A custom check that raises unconditionally, so `Ash.can?/3` is
  # exercised on its documented raise path (per `Ash.Can.can?/4`: any
  # `{:error, error}` result — including one caused by a raise inside a
  # check — is re-raised, not returned as `{:ok, false}`).
  defmodule RaisingCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck
    def describe(_opts), do: "always raises"
    def match?(_actor, _context, _opts), do: raise("boom")
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource KumiAdmin.CapabilityTest.ReadOnly
      resource KumiAdmin.CapabilityTest.RoleGated
      resource KumiAdmin.CapabilityTest.Flaky
    end
  end

  # No create/update action at all.
  defmodule ReadOnly do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy]
    end

    attributes do
      uuid_primary_key :id
    end
  end

  # Create/update exist, but are gated by RoleCheck.
  defmodule RoleGated do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy, create: :*, update: :*]
    end

    attributes do
      uuid_primary_key :id
    end

    policies do
      policy always() do
        authorize_if RoleCheck
      end
    end
  end

  # Create/update exist, but the policy check raises.
  defmodule Flaky do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy, create: :*, update: :*]
    end

    attributes do
      uuid_primary_key :id
    end

    policies do
      policy always() do
        authorize_if RaisingCheck
      end
    end
  end

  describe "missing action" do
    test "can_create?/2 is false when the resource has no create action" do
      refute Capability.can_create?(ReadOnly, %{role: :admin})
    end

    test "can_update?/2 is false when the resource has no update action" do
      # can_update?/2 only inspects the resource's action list, never the
      # record's data, so a bare struct (no create action exists to make a
      # real one) is enough.
      record = %ReadOnly{id: Ash.UUID.generate()}
      refute Capability.can_update?(record, %{role: :admin})
    end
  end

  describe "real policy passthrough" do
    test "can_create?/2 is true when the actor satisfies the resource's policy" do
      assert Capability.can_create?(RoleGated, %{role: :admin})
    end

    test "can_create?/2 is false when the actor fails the resource's policy" do
      # This is the assertion that would fail if `can_create?/2` were
      # simplified to always return `true` (the fail-open default) instead
      # of actually consulting `Ash.can?/3`.
      refute Capability.can_create?(RoleGated, %{role: :guest})
    end
  end

  describe "fail-open rescue" do
    # Documented behaviour (see `KumiAdmin.Capability`'s `safe_can?/2`):
    # write-time actions remain the authoritative check when `Ash.can?/3`
    # can't cheaply answer — this only governs whether the button renders.
    test "can_create?/2 returns true when Ash.can?/3 raises" do
      assert Capability.can_create?(Flaky, %{role: :admin})
    end

    test "can_destroy?/2 returns true when Ash.can?/3 raises" do
      {:ok, record} =
        Flaky
        |> Ash.Changeset.for_create(:create, %{}, authorize?: false)
        |> Ash.create(authorize?: false)

      assert Capability.can_destroy?(record, %{role: :admin})
    end
  end
end
