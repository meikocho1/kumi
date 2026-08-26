# Kumi

> Safe schema plans for [Ash](https://ash-hq.org) applications.
> Diffs your Ash resources (desired) against your live PostgreSQL database
> (actual), detects drift, and classifies every change as
> `SAFE` / `REVIEW` / `DANGEROUS`.

**Status: pre-alpha (v0.1). Not yet published to Hex. APIs will change.**

## Why, when `mix ash.codegen` already exists

`ash.codegen` diffs your resources against **its own snapshots** — your code's
history. Kumi diffs your resources against **the database itself** (pg_catalog).
That difference matters exactly when the two disagree:

```text
ash.codegen:   Current Resources  vs  Previous Snapshots   (code history)
kumi.plan:     Desired Resources  vs  Actual PostgreSQL    (live database)
```

A column someone added by hand in production is invisible to `ash.codegen`
and reported by `mix kumi.plan` as drift. Kumi complements codegen; it does
not replace it.

## Quick start

Not on Hex yet, so `mix igniter.install kumi` doesn't resolve a package
yet — use a path dependency plus the installer directly:

```elixir
# mix.exs
{:kumi, path: "../kumi"}
```

```bash
mix deps.get
mix kumi.install   # generates lib/<app>/app.ex — a `use Kumi.App` skeleton
```

(Once published to Hex, `mix igniter.install kumi` will do both steps —
add the dependency and run the installer — in one command, the same way
`mix igniter.install ash` works today.)

Add your Ash resources to the generated `resources do ... end` block, then:

```bash
mix kumi.plan            # human-readable plan
mix kumi.plan --verbose  # + provenance for each judgment
mix kumi.plan --check    # CI: exit 1 if anything needs REVIEW or is DANGEROUS
```

Want the admin UI too? Add `{:kumi_admin, path: "../kumi_admin"}` and run
`mix kumi_admin.install` — it mounts `KumiAdmin.Router`'s `kumi_admin/2`
into your Phoenix router (auto-wiring the actor when it can confirm an
`ash_authentication_phoenix`-style `LiveUserAuth` hook, otherwise printing
the exact mount snippet to add yourself instead of guessing).

Example output:

```text
crm_accounts:
  + column notes text  [SAFE: adds nullable column notes]
  ~ column industry (nullable: true -> false)  [REVIEW: tightens industry to NOT NULL — existing NULLs would fail]
  - column legacy_notes text  (in DB, not in code — drift)  [DANGEROUS: drops column legacy_notes — data loss]

1 safe / 1 review / 1 dangerous
```

Programmatic API (no global config is read by library code):

```elixir
%Kumi.Plan{} = Kumi.plan(MyApp.Repo, [MyApp.Domain], snapshot_dir: "priv/resource_snapshots/repo")
```

## Safety classification

One consistent rule set (see `Kumi.Plan.Safety` moduledoc):

| Level | Meaning | Examples |
|---|---|---|
| `SAFE` | Pure additions | new table, nullable column, non-unique index |
| `REVIEW` | Tightens constraints, or a guess | NOT NULL, unique index, FK changes on existing tables, possible renames |
| `DANGEROUS` | Would delete data | drop table, drop column, non-widening type change (unknown pairs fail closed) |

Rename detection uses AshPostgres snapshots as a **historical hint**: a
same-table, same-type remove+add pair whose old name appears in snapshot
history (and new name never does) is upgraded to `possible_rename` (REVIEW).
Ambiguity means no guess — false negatives over false positives.

## Sources of truth

```text
Desired  = your Ash resources (code — the source of truth)
Actual   = pg_catalog introspection (what the DB really contains)
Hint     = AshPostgres snapshots (history; rename disambiguation only)
```

## Known limitations

- `timestamp(0)` vs `timestamp(6)` precision changes are not detected
  (comparison is by `udt_name` only).
- Snapshot parsing depends on AshPostgres's internal, undocumented snapshot
  JSON format — an AshPostgres upgrade may break rename hints (covered by
  tests against real snapshot files, so breakage is caught loudly).
- Data-aware checks ("this NOT NULL change would fail on 143 existing NULLs")
  are planned but not implemented; classification is catalog-based only.
- Verified against a single host application so far.

## Development

Requires PostgreSQL (tests expect `localhost:5434`, user/password `postgres`,
and create their own `kumi_test` database):

```bash
mix deps.get
mix test
```

## Part of the Kumi project

This package is the first piece ("the wedge") of a larger effort:
an application platform on Phoenix/Ash where humans and AI agents modify
only application definitions, and tooling guarantees safe, reviewable
paths to production.

> Ash helps you model your application. Kumi helps you ship it as a product.

## License

TBD (Apache-2.0 planned; final decision pending trademark/name checks).
