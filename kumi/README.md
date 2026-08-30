# Kumi

> Safe schema plans for [Ash](https://ash-hq.org) applications.
> Diffs your Ash resources (desired) against your live PostgreSQL database
> (actual), detects drift, and classifies every change as
> `SAFE` / `REVIEW` / `DANGEROUS`.

Pre-alpha (v0.1), not on Hex, APIs will change. A side project, used on a
personal Ash app, never run against production traffic.

## Why, when `mix ash.codegen` already exists

Codegen diffs your resources against snapshots it wrote itself. That is
your code's history, and it is the right thing to look at nearly all of
the time. Nothing in that path opens a connection to the database.

```text
ash.codegen:   Current Resources  vs  Previous Snapshots   (code history)
kumi.plan:     Desired Resources  vs  Actual PostgreSQL    (live database)
```

So anything that changed in the database outside a migration is invisible
to codegen, permanently. `mix kumi.plan` reports it as drift.

The two answer different questions and both are worth running. Kumi does
not replace codegen.

### What makes it more than a diff

Any of us could read `pg_catalog`. The part worth arguing about is that
every difference is classified by whether resolving it destroys data, and
that type changes fail closed: if Kumi cannot prove a change is widening,
it says DANGEROUS. That will produce false alarms. A false DANGEROUS costs
you a second look, a missed one costs you a column, and that trade is the
whole design.

Classification never reads your data, only the schema. `--probe` adds
read-only counts as annotations and is forbidden from changing a verdict,
so `mix kumi.plan --check` means the same thing in CI regardless of which
database it ran against.

## Quick start

### New project

Starting from nothing? `mix kumi.new` runs `mix igniter.new` with
Ash/Phoenix/Ash Authentication, wires in Kumi (+ kumi_admin), configures
the DB, and installs everything — one command to a running app:

```bash
mix archive.install hex igniter_new
mix archive.install hex phx_new
(cd ../kumi_new && mix archive.build && mix archive.install)  # not on Hex yet, confirms [Yn]
mix kumi.new my_crm --kumi-path .. --db-port 5434
```

Want optional modules (e.g. file/image uploads) wired in too? Add `--with
storage`, or run interactively (no `--with`/`--no-modules`, TTY shell) and
pick from the printed catalog.

(Once Kumi ships to Hex, `--kumi-path` becomes optional.)

### Existing app

Not on Hex yet, so `mix igniter.install kumi` doesn't resolve a package
yet — use a path dependency plus the installer directly:

```elixir
# mix.exs
{:kumi, path: "../kumi"}
```

```bash
mix deps.get
mix kumi.install   # generates lib/<app>/app.ex — a `use Kumi.App` skeleton —
                   # plus an <App>.Core domain, registered in :ash_domains
```

(Once published to Hex, `mix igniter.install kumi` will do both steps —
add the dependency and run the installer — in one command, the same way
`mix igniter.install ash` works today.)

Add your Ash resources under `<App>.Core`, then list them in the generated
`resources do ... end` block, then:

```bash
mix kumi.plan            # human-readable plan
mix kumi.plan --verbose  # + provenance for each judgment
mix kumi.plan --check    # CI: exit 1 if anything needs REVIEW or is DANGEROUS
mix kumi.apply           # dev-only: executes the SAFE drift-repair subset of the plan
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

- Snapshot parsing depends on AshPostgres's internal, undocumented snapshot
  JSON format — an AshPostgres upgrade may break rename hints (covered by
  tests against real snapshot files, so breakage is caught loudly).
- Data-aware checks ("this NOT NULL change would fail on 143 existing NULLs")
  are planned but not implemented; classification is catalog-based only.
- Verified against a single host application so far.

See [guides/ash-gotchas.md](guides/ash-gotchas.md) for Ash/Spark/AshPostgres/Igniter gotchas found while building Kumi.

See [guides/auth.md](guides/auth.md) for sign-in strategies, multi-provider (Google/GitHub/OIDC) setup, and two-factor auth.

See [guides/mini-crm.md](guides/mini-crm.md) for a from-scratch walkthrough building a CRM with Kumi and official Ash libraries.

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

MIT — see [`LICENSE`](LICENSE).
