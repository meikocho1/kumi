defmodule Kumi.Plan.RenameRealSnapshotsTest do
  # Canary (F20 in the spike's friction log): does Kumi.Plan.Rename's
  # snapshot-history loader still parse the REAL AshPostgres snapshot JSON
  # format, not a hand-built imitation of it? `test/fixtures/resource_snapshots`
  # is a checked-in copy of a real snapshot captured from spike0_crm's
  # crm_accounts resource (priv/resource_snapshots/repo/crm_accounts/).
  #
  # The spike's version of this test drove the scenario off
  # `Kumi.Desired.extract/0` against the real spike domain — that dependency
  # doesn't exist standalone, so here the "developer renamed `name` to
  # `full_name`" remove/add pair is built by hand instead. The real snapshot
  # file is what's actually under test.
  use ExUnit.Case, async: true

  alias Kumi.Plan.{Format, Rename}
  alias Kumi.Schema.Column

  @snapshot_dir Path.join([File.cwd!(), "test", "fixtures", "resource_snapshots"])

  test "rename detection against the real, on-disk AshPostgres snapshot format" do
    old = %Column{name: "name", type: "text", nullable: false}
    new = %Column{name: "full_name", type: "text", nullable: false}

    ops = [{:remove_column, "crm_accounts", old}, {:add_column, "crm_accounts", new}]

    assert [{:possible_rename, "crm_accounts", ^old, ^new}] = Rename.detect(ops, @snapshot_dir)

    resolved = Rename.detect(ops, @snapshot_dir)
    assert Format.format(resolved, verbose: true, snapshot_dir: @snapshot_dir) =~ "via: #{@snapshot_dir}"
  end
end
