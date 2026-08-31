defmodule KumiAdmin.FormatTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Format

  test "cell/2 truncates :id values" do
    id = "550e8400-e29b-41d4-a716-446655440000"
    assert Format.cell(:id, id) == "550e8400…"
  end

  test "cell/2 shortens DateTime values" do
    {:ok, dt, _} = DateTime.from_iso8601("2026-08-26T14:30:05Z")
    assert Format.cell(:inserted_at, dt) == "2026-08-26 14:30"
  end

  test "cell/2 renders nil as an em dash" do
    assert Format.cell(:industry, nil) == "—"
  end

  test "cell/2 renders atoms and falls back to to_string/1" do
    assert Format.cell(:stage, :lead) == "lead"
    assert Format.cell(:name, "Acme") == "Acme"
  end

  test "cell/3 truncates the declared foreign keys, not other strings" do
    uuid = "d807c77b-e7a2-4ef1-85c6-a267c46805b9"

    assert Format.cell(:account_id, uuid, [:account_id]) == "d807c77b…"
    assert Format.cell(:name, uuid, [:account_id]) == uuid
  end

  # P05: `external_id` / `stripe_customer_id` are ordinary business columns,
  # not foreign keys — truncating them by name made the value unreadable.
  test "cell/3 leaves an `_id`-suffixed column that is not a foreign key intact" do
    assert Format.cell(:external_id, "cus_9f2Ab7QhVzKp", [:account_id]) ==
             "cus_9f2Ab7QhVzKp"
  end

  test "cell/2 without a foreign key list truncates nothing but :id" do
    uuid = "d807c77b-e7a2-4ef1-85c6-a267c46805b9"

    assert Format.cell(:account_id, uuid) == uuid
    assert Format.cell(:id, uuid) == "d807c77b…"
  end
end
