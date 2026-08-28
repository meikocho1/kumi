defmodule Kumi.Probe do
  @moduledoc """
  Data-aware safety probes: read-only queries against the LIVE database that
  give a human reviewer a concrete row count alongside a `Kumi.Plan`
  operation's classification. See `Kumi.Plan.Finding` for why probes
  ANNOTATE a plan rather than reclassify it.

  Opt-in only — see `Kumi.plan/3`'s `:probe` option, `false` by default per
  blueprint §3.4 ("Stage 2 reads live data, opt in explicitly"). Every other
  Kumi module either reads schema-only metadata (`Kumi.Actual`, via
  pg_catalog/information_schema) or touches no database at all; this is the
  one module that runs `SELECT count(*)`-shaped queries against the actual
  application tables.

  Probed today (see moduledoc-level rationale for why these five and not
  more): NOT NULL tightening (existing NULL count), a new unique index or
  identity (duplicate-group count), `remove_column` (non-null count — data
  that would be lost), `drop_table` (row count), and a type change (row
  count only — casting a real value through the new type to see if it would
  fail is out of scope for this version, see the friction log).

  All queries are read-only SELECTs. Table/column names come from
  `Kumi.Actual`/`Kumi.Desired` (pg_catalog and Ash introspection — not
  end-user input), but every one is still passed through `quote_ident/1`
  rather than interpolated raw, so a name that needs quoting (mixed case, a
  reserved word) produces valid SQL instead of a syntax error or a
  silently-wrong query.

  Known ceiling: every probe is an unqualified `count(*)` (or `count(*)`
  over a `GROUP BY ... HAVING` subquery) — no `LIMIT`, no sampling. On a
  very large table this is a real sequential-scan cost at plan time. Not
  addressed here; see the v0.1.5 friction log.
  """

  alias Kumi.Plan.Finding
  alias Kumi.Schema.{Ident, Index}

  @spec run(module(), Kumi.Plan.t()) :: [Finding.t()]
  def run(repo, %Kumi.Plan{entries: entries}) do
    Enum.flat_map(entries, fn {op, _level, _reason} -> probe(repo, op) end)
  end

  defp probe(repo, {:change_column, table, col, changes} = op) do
    Enum.flat_map(changes, fn
      {:nullable, false, true} -> [null_count_finding(repo, op, table, col)]
      {:type, _desired, _actual} -> [type_change_finding(repo, op, table, col)]
      _other -> []
    end)
  end

  defp probe(repo, {:remove_column, table, col} = op) do
    sql = "SELECT count(*) FROM #{quote_ident(table)} WHERE #{quote_ident(col.name)} IS NOT NULL"
    count = scalar!(repo, sql)

    [
      %Finding{
        op: op,
        query_description: "count(*) FROM #{table} WHERE #{col.name} IS NOT NULL",
        count: count,
        note: "#{count} rows contain data that would be lost"
      }
    ]
  end

  defp probe(repo, {:drop_table, table} = op) do
    sql = "SELECT count(*) FROM #{quote_ident(table.name)}"
    count = scalar!(repo, sql)

    [
      %Finding{
        op: op,
        query_description: "count(*) FROM #{table.name}",
        count: count,
        note: "table contains #{count} rows"
      }
    ]
  end

  defp probe(repo, {:add_index, table, %Index{unique: true} = idx} = op) do
    [duplicate_count_finding(repo, op, table, idx)]
  end

  defp probe(_repo, _op), do: []

  defp null_count_finding(repo, op, table, col) do
    sql = "SELECT count(*) FROM #{quote_ident(table)} WHERE #{quote_ident(col.name)} IS NULL"
    count = scalar!(repo, sql)

    %Finding{
      op: op,
      query_description: "count(*) FROM #{table} WHERE #{col.name} IS NULL",
      count: count,
      note: "#{count} existing NULL rows would fail"
    }
  end

  defp type_change_finding(repo, op, table, col) do
    sql = "SELECT count(*) FROM #{quote_ident(table)}"
    count = scalar!(repo, sql)

    %Finding{
      op: op,
      query_description:
        "count(*) FROM #{table} (row count only — no cast probing for #{col.name})",
      count: count,
      note:
        "#{count} rows total — whether they would cast cleanly to the new type was not checked"
    }
  end

  defp duplicate_count_finding(repo, op, table, idx) do
    quoted_cols = Enum.map(idx.columns, &quote_ident/1)
    not_null_clause = Enum.map_join(idx.columns, " AND ", &"#{quote_ident(&1)} IS NOT NULL")

    sql = """
    SELECT count(*) FROM (
      SELECT 1 FROM #{quote_ident(table)}
      WHERE #{not_null_clause}
      GROUP BY #{Enum.join(quoted_cols, ", ")}
      HAVING count(*) > 1
    ) dup
    """

    count = scalar!(repo, sql)

    %Finding{
      op: op,
      query_description: "duplicate groups on (#{Enum.join(idx.columns, ", ")}) in #{table}",
      count: count,
      note: "#{count} duplicate value groups would violate uniqueness"
    }
  end

  @doc """
  Quotes a Postgres identifier. Delegates to `Kumi.Schema.Ident` — the one
  shared implementation, also used by `Kumi.Plan.SQL` (see that module and
  `Kumi.Schema.Ident`'s moduledoc for why this used to be duplicated and
  why it no longer is). Kept as a public function here since existing
  callers/tests reach it as `Kumi.Probe.quote_ident/1`.
  """
  @spec quote_ident(String.t()) :: String.t()
  defdelegate quote_ident(name), to: Ident

  defp scalar!(repo, sql) do
    %{rows: [[count]]} = Ecto.Adapters.SQL.query!(repo, sql, [])
    count
  end
end
