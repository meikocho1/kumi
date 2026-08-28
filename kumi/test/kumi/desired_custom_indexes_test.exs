defmodule Kumi.DesiredCustomIndexesTest do
  # M2: Kumi.Desired.indexes/2 used to only look at Ash `identities`, missing
  # AshPostgres's own `postgres do custom_indexes do ... end end` section.
  # Kumi.Actual introspects EVERY non-PK pg_index, so a host that declares a
  # custom_indexes entry, runs `mix ash.codegen`, and migrates ended up with
  # a real `mix kumi.plan --check` failure forever (a `remove_index` that
  # never goes away — see the moduledoc note on Kumi.Desired.custom_indexes/2).
  #
  # Kumi.Test.Deal (test/support/test_deal.ex) carries exactly this:
  # `custom_indexes do index [:amount] end`, no explicit name — generated
  # via `MIX_ENV=test mix ash.codegen add_amount_custom_index` and migrated
  # into the real kumi_test database, so this test is against the real
  # thing, not a synthetic struct.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Schema.Index

  test "a custom_indexes entry appears on the desired side with AshPostgres's own default name" do
    desired = Kumi.Desired.extract([Kumi.Test.Domain])
    deals = Enum.find(desired, &(&1.name == "kumi_test_deals"))

    assert %Index{name: "kumi_test_deals_amount_index", columns: ["amount"], unique: false} =
             Enum.find(deals.indexes, &(&1.name == "kumi_test_deals_amount_index"))
  end

  test "no phantom remove_index for it — desired and actual agree" do
    desired = Kumi.Desired.extract([Kumi.Test.Domain, Kumi.Test.ResourceDomain])
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)

    diff = Kumi.Diff.diff(desired, actual)

    refute Enum.any?(diff, &match?({:remove_index, "kumi_test_deals", _}, &1))
    refute Enum.any?(diff, &match?({:add_index, "kumi_test_deals", _}, &1))
  end
end
