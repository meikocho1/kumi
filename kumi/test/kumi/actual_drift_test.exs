defmodule Kumi.ActualDriftTest do
  # Simulates the exact scenario `mix ash.codegen` cannot see: a column added
  # directly in the database, outside of any Ash migration. Kumi.Actual must
  # pick it up from pg_catalog, and Kumi.Diff must report it as drift
  # (present in the DB, absent from the code) rather than silently ignoring it.
  #
  # The ALTER TABLE runs inside the DataCase sandbox transaction, so it is
  # rolled back automatically at the end of the test — no manual DROP COLUMN
  # / on_exit needed.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Schema.Column

  test "a manually-added column is reported as a drifted remove_column" do
    Ecto.Adapters.SQL.query!(
      Kumi.Test.Repo,
      "ALTER TABLE kumi_test_accounts ADD COLUMN legacy_phone text",
      []
    )

    desired = Kumi.Desired.extract([Kumi.Test.Domain, Kumi.Test.ResourceDomain])
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)

    diff = Kumi.Diff.diff(desired, actual)

    assert [{:remove_column, "kumi_test_accounts", %Column{} = col}] = diff
    assert col.name == "legacy_phone"
    assert col.type == "text"
    assert col.nullable == true
    assert col.default == nil
  end
end
