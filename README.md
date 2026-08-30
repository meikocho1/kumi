<p align="center">
  <img src="design/kumi-logo.svg" alt="Kumi" width="88" height="88">
</p>

<h1 align="center">Kumi</h1>

<p align="center">
  <strong>Ash helps you model your application. Kumi helps you ship it as a product.</strong>
</p>

<p align="center">
  <a href="https://github.com/meikocho1/kumi/actions/workflows/ci.yml"><img src="https://github.com/meikocho1/kumi/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/elixir-~%3E%201.20-purple.svg" alt="Elixir">
</p>

Kumi is an application platform for [Ash](https://ash-hq.org) and Phoenix.
You define your resources in code; Kumi gives you a real admin UI, a login
flow, safe database plans, and a one-command generator to start from —
without hiding Ash from you at any point.

## The 30-second version

**Your migrations tell you what your code did. They don't tell you what your
database *is*.** `mix ash.codegen` compares your code to its own snapshots.
Kumi compares your code to the live database, and classifies every
difference by whether it can lose data:

```text
crm_accounts:
  + column notes text  [SAFE: adds nullable column notes]
  ~ column industry (nullable: true -> false)  [REVIEW: tightens industry to NOT NULL — existing NULLs would fail]
  - column legacy_notes text  (in DB, not in code — drift)  [DANGEROUS: drops column legacy_notes — data loss]

1 safe / 1 review / 1 dangerous
```

That column someone added by hand in production, three months ago, that
nobody wrote down? `ash.codegen` cannot see it. This is the whole point.
`mix kumi.plan --check` puts it in CI, and `mix kumi.apply` repairs the
SAFE subset in dev — never the rest.

Then, because your resources are already declared, you get the rest of the
product shell for free:

<p align="center">
  <img src="design/screenshots/kumi-detail-atomic-child.png" alt="A Kumi admin record page — attributes, an enum stage badge, and resolved belongs_to relations — generated from Ash resources with no per-resource code" width="860">
</p>

Tables, forms, search, `belongs_to` selects, child tables, dashboard
metrics and workflow stages — derived from the resources you already
wrote, with **no per-resource admin code**, and no authentication of its
own: it sits behind whatever your app already uses
([Google, GitHub, OIDC and friends](kumi/guides/auth.md)).

## How is this different from `ash_admin`?

`ash_admin` is a developer's inspector for your data — excellent at that,
and deliberately generic. Kumi is aimed at the thing you hand to a
non-developer: an app-level DSL where *you* declare the navigation,
dashboard metrics and workflow stages, plus the plan engine and the
generator around it. If you want to browse your resources in dev, use
`ash_admin`. If you want the admin to be the product, that's this.

## What's in here

Four independent mix packages, released together:

| Package | What it gives you |
|---|---|
| **[`kumi/`](kumi/)** | `mix kumi.plan` — a diff between your Ash resources and your **live** Postgres database, with every change classified `SAFE` / `REVIEW` / `DANGEROUS`. Plus `mix kumi.apply` for safe drift repair, the app-level DSL, and a resource shorthand that prints exactly what it compiles to. |
| **[`kumi_admin/`](kumi_admin/)** | A LiveView admin derived from your resources — tables, forms, search, `belongs_to` selects, child tables, dashboard metrics, workflow stages. No per-resource code, and no authentication of its own: it sits behind whatever your app already uses. |
| **[`kumi_storage/`](kumi_storage/)** | Uploads, as an installable module. Generates a plain Ash resource with an `:upload` action; the admin picks it up automatically. |
| **[`kumi_new/`](kumi_new/)** | `mix kumi.new my_app` — from nothing to a running application with an admin and a login screen, in one command. |

**Status: pre-release.** MIT licensed and buildable today, but nothing is
published to Hex yet and APIs will change before the first tag. See
[`RELEASING.md`](RELEASING.md) for what's left.

## Three things Kumi will not do

These are settled design decisions, not gaps:

1. **It will never hide Ash.** Every Kumi DSL compiles to ordinary,
   inspectable Ash resources, `mix kumi.expand` always prints exactly
   what compiles, and writing plain Ash is a supported escape hatch
   rather than a fallback for when Kumi breaks. Anything the shorthand
   can't round-trip through `kumi.expand` is intentionally left out —
   you drop to Ash for it.
2. **It targets Ash/AshPostgres only.** No Ecto adapter, no persistence
   abstraction.
3. **It complements `mix ash.codegen`, it doesn't replace it.**
   `ash.codegen` compares your code to its own snapshots — your code's
   history. Kumi compares your code to the database itself, which is a
   different question, and the one that catches a column someone added by
   hand in production.

## Quick look

Kumi is not on Hex yet, so `mix kumi.new` comes from a locally built
archive and needs `--kumi-path` pointing at this checkout. Run this from
the directory *above* your Kumi clone:

```bash
mix archive.install hex igniter_new
mix archive.install hex phx_new
(cd Kumi/kumi_new && mix archive.build && mix archive.install)  # confirms [Yn]

# Start a new project — Ash, Phoenix, authentication, admin, database.
mix kumi.new my_crm --kumi-path Kumi --db-port 5434
```

(Once Kumi ships to Hex, `--kumi-path` and the archive build both go away.)

`--kumi-path` must be the checkout's *real* path — pass a symlink to it and
Mix rejects the generated project with "the dependency kumi in mix.exs is
overriding a child dependency", because the absolute path written into your
`mix.exs` no longer matches the `../kumi` that `kumi_admin` declares.

Then, from inside `my_crm/`:

```bash
# What does my database actually look like, versus my code?
mix kumi.plan
#   SAFE       add_column accounts.industry (text, nullable)
#   REVIEW     possible_rename accounts.title -> accounts.name
#   DANGEROUS  remove_column accounts.legacy_code  (deletes data)

# Repair only the safe drift, in dev, in one transaction.
mix kumi.apply

# What does this shorthand resource really compile to?
mix kumi.expand MyCrm.Core.Account
```

Adding Kumi to an **existing** app instead? See
[`kumi/README.md`](kumi/README.md#existing-app).

## Documentation

- **[`kumi/README.md`](kumi/README.md)** — install, the plan engine, the
  DSLs, every mix task.
- **[`kumi_admin/README.md`](kumi_admin/README.md)** — mounting the admin,
  every router option, and the two things that bite newcomers (no auth of
  its own; every managed resource needs an `:id` primary key).
- **[`kumi_storage/README.md`](kumi_storage/README.md)** — uploads: install,
  the `:image` field, validation defaults, the backend contract.
- **[`kumi/guides/mini-crm.md`](kumi/guides/mini-crm.md)** — build a
  small CRM end to end. Every snippet in it was executed.
- **[`kumi/guides/api.md`](kumi/guides/api.md)** — adding a JSON:API when
  you need one, and how relationship depth works.
- **[`kumi/guides/auth.md`](kumi/guides/auth.md)** — sign-in strategies,
  `mix kumi.gen.auth google` for the OAuth2 providers that have no
  upstream installer, and where two-factor auth actually has to come from.
- **[`kumi/guides/frontend.md`](kumi/guides/frontend.md)** — putting your
  public-facing frontend on the same Phoenix app as the admin, including
  the security headers that will otherwise silently break embedding.
- **[`kumi/guides/ash-gotchas.md`](kumi/guides/ash-gotchas.md)** — the
  non-obvious Ash / Spark / AshPostgres / Igniter behaviours that cost
  real debugging time while building this.

## Requirements

Elixir and OTP as pinned in [`.tool-versions`](.tool-versions), and
PostgreSQL 17.

## Contributing

Bug reports, features and PRs are welcome — see
**[`CONTRIBUTING.md`](CONTRIBUTING.md)** for setup, the checks CI runs,
and what a reviewer looks for. Security issues go through private
reporting instead: **[`SECURITY.md`](SECURITY.md)**.

## License

MIT — see [`LICENSE`](LICENSE).
