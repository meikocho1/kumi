defmodule Kumi.DiffMissingColumnTest do
  # No code/DB changes here — pure data manipulation. We take the real
  # desired schema and add a column to it that the (real, unmodified)
  # database does not have, then assert Kumi.Diff notices the DB is
  # missing something the code now wants.
  use Kumi.Test.DataCase, async: false

  alias Kumi.Schema.Column

  test "a column present in desired but absent from actual is an add_column" do
    actual = Kumi.Actual.introspect(Kumi.Test.Repo)

    desired =
      [Kumi.Test.Domain]
      |> Kumi.Desired.extract()
      |> Enum.map(fn table ->
        if table.name == "kumi_test_accounts" do
          synthetic = %Column{name: "loyalty_tier", type: "text", nullable: true, default: nil}
          %{table | columns: [synthetic | table.columns]}
        else
          table
        end
      end)

    diff = Kumi.Diff.diff(desired, actual)

    assert Enum.any?(
             diff,
             &match?({:add_column, "kumi_test_accounts", %Column{name: "loyalty_tier"}}, &1)
           )
  end
end
