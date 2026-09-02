defmodule Kumi.DescribeTest do
  @moduledoc """
  The contract test for `mix kumi.describe` (blueprint §8 point 4).

  A literal golden fixture, not structural assertions: the point of
  `schema_version` is that consumers can rely on the shape, so a renamed
  key has to fail here rather than slide past an `is_map/1`.
  """
  use ExUnit.Case, async: true

  @fixture Path.join(__DIR__, "../fixtures/describe_test_app.json")

  test "the app model is exactly the recorded contract" do
    assert Kumi.Describe.encode(Kumi.Test.App) == File.read!(@fixture)
  end

  test "plan state is the shared Kumi.Plan.Json shape, not a second encoding" do
    plan = %Kumi.Plan{
      entries: [
        {{:remove_column, "kumi_test_accounts", %{name: :legacy}}, :dangerous, "deletes data"}
      ],
      safe: 0,
      review: 0,
      dangerous: 1
    }

    assert Kumi.Describe.to_map(Kumi.Test.App, plan).plan == Kumi.Plan.Json.to_map(plan)
  end

  test "no plan is null, so --no-plan output stays valid against the same schema" do
    assert Kumi.Describe.to_map(Kumi.Test.App).plan == nil
  end
end
