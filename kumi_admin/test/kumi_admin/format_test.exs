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
end
