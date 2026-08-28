defmodule KumiAdmin.SearchTest do
  @moduledoc """
  `KumiAdmin.Search` takes user-controlled query input straight into an Ash
  filter, so these tests run real queries (via `KumiAdmin.Test.Widget`, an
  in-memory `Ash.DataLayer.Ets` fixture already defined in test/support —
  private ETS tables are process-scoped, so no cross-test cleanup is
  needed) rather than asserting on the built `Ash.Query` shape.
  """

  use ExUnit.Case, async: true

  alias KumiAdmin.Search
  alias KumiAdmin.Test.Widget

  defp create!(attrs) do
    {:ok, record} = Widget |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    record
  end

  defp search(fields, term) do
    Widget
    |> Ash.Query.for_read(:read)
    |> Search.apply(fields, term)
    |> Ash.read!()
  end

  test "searchable_fields/1 lists only public string-typed attributes, excluding the private one" do
    # Widget declares public a..f + description (string), plus active/scheduled_on/price/status
    # (non-string) and a private `hidden` string. If `hidden` ever leaked in here, a search term
    # matching only its value would return results it must not.
    assert Search.searchable_fields(Widget) == [:a, :b, :c, :d, :e, :f, :description]
  end

  test "apply/3 is case-insensitive: a fully-uppercase term matches a mixed-case value" do
    ada = create!(%{a: "Ada Lovelace"})
    _bob = create!(%{a: "Bob"})

    fields = Search.searchable_fields(Widget)
    results = search(fields, "ADA")

    # This is the assertion that fails the moment `Ash.CiString.new(term)` in
    # `Search.apply/3` is replaced by a plain string: `contains/2` against a
    # `:string` field is case-sensitive, and "ADA" would then match nothing.
    assert Enum.map(results, & &1.id) == [ada.id]
  end

  test "apply/3 cannot reach a private attribute even when its value matches the term" do
    create!(%{a: "irrelevant"})

    secret =
      Widget
      |> Ash.Changeset.for_create(:create, %{a: "also irrelevant"})
      # `hidden` is `public? false`, so the default `create: :*` action does not
      # accept it as input — force it directly to seed the fixture.
      |> Ash.Changeset.force_change_attribute(:hidden, "topsecret")
      |> Ash.create!()

    fields = Search.searchable_fields(Widget)
    refute :hidden in fields

    # Proves the restriction is load-bearing end to end: searching for the
    # exact private value returns nothing, because `filter_input/2` only ever
    # sees the public field list `apply/3` was given.
    results = search(fields, "topsecret")
    assert results == []
    assert secret.hidden == "topsecret"
  end

  test "apply/3 with a blank term returns the query unchanged" do
    fields = Search.searchable_fields(Widget)
    query = Ash.Query.for_read(Widget, :read)

    assert Search.apply(query, fields, "") == query
    assert Search.apply(query, fields, nil) == query
  end

  test "apply/3 treats a whitespace-only term as a literal search value, not as blank" do
    # Documented observation, not an assumption: unlike "" and nil, a
    # whitespace-only term does NOT hit the blank guard in `Search.apply/3`
    # (`term in [nil, ""]`) — it falls through to the real filter and is
    # searched for literally. Verified empirically against this fixture:
    # no widget contains a literal 3-space run, so it matches nothing (it
    # does not behave as "match everything" either). Whether whitespace
    # should be normalised to blank is a product decision outside this
    # module's tested contract, not a bug this test is asserting.
    create!(%{a: "some value"})
    fields = Search.searchable_fields(Widget)

    assert search(fields, "   ") == []
  end

  test "apply/3 treats a `%` in the term as a literal character, not a SQL-style wildcard" do
    percent = create!(%{a: "100% approved"})
    _plain = create!(%{a: "totally approved"})

    fields = Search.searchable_fields(Widget)
    results = search(fields, "%")

    # If `contains/2` ever compiled `%` down to an unescaped LIKE wildcard,
    # this term would match every row instead of just the one containing a
    # literal percent sign.
    assert Enum.map(results, & &1.id) == [percent.id]
  end

  test "apply/3 treats a `_` in the term as a literal character, not a SQL-style single-char wildcard" do
    underscored = create!(%{a: "a_b"})
    _other = create!(%{a: "axb"})

    fields = Search.searchable_fields(Widget)
    results = search(fields, "_")

    assert Enum.map(results, & &1.id) == [underscored.id]
  end
end
