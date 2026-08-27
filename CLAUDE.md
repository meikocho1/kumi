# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Kumi — an application platform on Phoenix/Ash ("Ash helps you model your application. Kumi helps you ship it as a product."). **`KUMI_PROJECT_BLUEPRINT_v3.md` is the Project Source of Truth**; v1/v2 are historical. Three decisions are locked (v3 §0) and must not be relitigated in code:

- **D1 Show Ash**: Kumi DSL compiles to real, inspectable Ash resources. Never hide Ash; writing plain Ash is the supported escape hatch, and `mix kumi.expand` must always print exactly what compiles.
- **D2 Single compile target**: Ash/AshPostgres only. No Ecto adapter, no persistence abstraction.
- **D3 Wedge-first**: `mix kumi.plan` (desired-vs-actual diff) is the adoption wedge; the platform (app DSL, admin) builds on it.

The project is private/pre-release. Do not publish (Hex, GitHub remote, push) — naming/license are undecided. Do not git commit unless the user asks. Write commit messages and PR text in English (OSS-ready — only `kumi/`, `kumi_admin/`, `kumi_new/` will be published; internal docs like the blueprints and friction log stay Japanese and private).

## Repo layout

Monorepo (this git repo) + one nested repo:

- `kumi/` — core package. **No Phoenix deps — keep it that way.** Schema diffing, safety classification, App/Resource DSLs, mix tasks.
- `kumi_admin/` — LiveView product shell consuming the App DSL. Deps: kumi (path), phoenix, phoenix_live_view, ash_phoenix.
- `kumi_storage/` — first real plugin (blueprint §6): `mix kumi_storage.install` generates a plain-Ash Attachment resource with an `:upload` action (validation + backend `store/4`) and a `__kumi_attachment_url__/1` URL contract; `:image` fields expand to it. Deps: kumi (path), ash, plug (no phoenix). `kumi_admin` drives it purely through the `__kumi_attachment__/0` marker + that convention action/URL function — no dependency on kumi_storage itself (admin deps stay kumi + phoenix + LV + ash_phoenix).
- `kumi_new/` — `mix kumi.new` project generator. **Zero runtime deps** (must stay archive-compatible like phx_new).
- `spikes/spike0_crm/` — real host app used as the integration testbed. **Its own git repo**, gitignored at root; commit its changes separately inside it.
- `spikes/chat_ops/` — second host app (blueprint §6 生態の順序): online-ops chat SaaS skeleton (embedded visitor widget + kumi_admin operator view), gitignored at root; not yet its own git repo (no auto-init from `kumi.new` this run).
- `spikes/FRICTION_LOG.md` — running log (F-numbered entries, Japanese) of everything learned building against Ash. **Appending honest friction entries is part of every feature's definition of done** — including what broke, what was reused, and deliberately-cut corners.

## Commands

Postgres runs in docker: container `kumi_db`, `postgres:17-alpine`, `localhost:5434`, user/password `postgres`. Package tests create their own DBs (`kumi_test`, `spike0_crm_test`).

Per package (run inside `kumi/`, `kumi_admin/`, `kumi_new/`, or `spikes/spike0_crm/`):

```bash
mix deps.get
mix test                          # kumi's test alias runs `ash.setup --quiet` first
mix test path/to/file_test.exs:42 # single test
mix compile --warnings-as-errors  # must stay clean (own code; upstream dep warnings excluded)
mix format --check-formatted      # all four trees are format-clean; keep them so
```

Kumi's own tasks (run inside a host app such as spike0_crm):

```bash
mix kumi.plan [--check] [--verbose] [--probe] [--app MyApp.App]
mix kumi.apply [--yes] [--app MyApp.App]   # SAFE drift repair only (allowlist+SQL-renderable), dev-only
mix kumi.expand My.Resource       # print the Ash source a shorthand resource compiles to
mix kumi.report [--json] [--skip-tests] [--strict]   # format/compile/test/codegen/plan → verdict
mix kumi.install                  # igniter installer (generates lib/<app>/app.ex + <App>.Core domain, registers it in ash_domains)
mix kumi_admin.install            # composes kumi.install + mounts the admin router
mix kumi_storage.install          # composes kumi.install + generates <App>.Core.Attachment, configures Local backend, mounts KumiStorage.Plug
mix kumi.new my_app --db-port 5434 --kumi-path /Users/akimitu/Documents/Kumi [--with storage]   # from anywhere
```

Gotcha: generating migrations for resources under `test/support` requires `MIX_ENV=test mix ash.codegen NAME` — without the env it silently generates nothing (friction log F27).

## Architecture (the parts that span files)

### The plan engine (kumi core)

Three sources with fixed roles — this resolves who wins when they disagree:

```
Desired = code (Ash resources; extracted via Ash.Resource.Info + AshPostgres introspection)
Actual  = live PostgreSQL (pg_catalog/information_schema; Kumi.Actual)
Hint    = AshPostgres snapshots (history only; used solely for rename disambiguation)
```

Pipeline: `Kumi.Desired.extract` + `Kumi.Actual.introspect` → `Kumi.Diff` (pure) → `Kumi.Plan.Rename.detect` → `Kumi.Plan.Safety.classify` → `%Kumi.Plan{}`. Two ordering/design invariants:

- **Rename detection must run before Safety.** Safety's single rule set depends on it: proposals that delete data = DANGEROUS (any `remove_column` not upgraded to `possible_rename`, `drop_table`, non-widening type change — unknown type pairs fail closed); constraint tightening or guesses = REVIEW; pure additions = SAFE.
- **Classification is deterministic from schema alone.** `Kumi.Probe` (opt-in, `probe: true` / `--probe`) runs read-only counts and attaches `findings` that annotate but never reclassify — `--check` exit codes must not depend on live data.

This is deliberately different from `mix ash.codegen` (code-vs-snapshot): Kumi sees manual DB drift that codegen can't. Kumi complements codegen, never replaces it.

### DSL ownership (two layers, no overlap)

- `Kumi.App` (Spark DSL): app-level intent only — name/title, `resources` (references to real Ash modules), admin navigation, workflow stages, dashboard metrics. It must never duplicate Ash's domain DSL (attributes/actions/policies). Introspection via `Kumi.App.Info`; compile-time verifiers reject non-Ash resources, navigation ⊄ resources, duplicates.
- `Kumi.Resource` (shorthand): sugar that expands to a standard Ash resource. Single source of truth is `Kumi.Resource.Codegen.generate/3` — both the macro and `mix kumi.expand` consume it, and a test proves expand output == compiled definition. If a feature can't keep that invariant, it doesn't go in the shorthand (policies/calculations/json_api are intentionally unsupported; users drop to plain Ash).
- Library code takes explicit args (`Kumi.plan(repo, domains, opts)`, `Kumi.plan_app(app)`); **only mix tasks read Application config** (via `Mix.Tasks.Kumi.Resolve`). `plan/3` is the whole-database view; `plan_app/2` filters BOTH desired and actual to the app's declared tables (out-of-scope tables are ignored, not drift).

### kumi_admin

Consumes `Kumi.App.Info` (navigation drives the sidebar with zero host code). Has **no auth of its own**: the router macro (`kumi_admin/2`, session-MFA pattern copied from ash_admin) takes the host's `on_mount` hooks and an `actor: {M, f}` (default reads `socket.assigns.current_user`). Policy-forbidden reads render an honest empty state, never a crash. New/Edit/Delete buttons are gated by `Ash.can?` (fail-open to the flash path). Column/widget derivation is pure (`Columns`, `FormFields`, `Search`) and unit-tested in the package; LiveView behavior is tested in spike0_crm.

## Hard-won gotchas (verified in this repo; see friction log for details)

- `Spark.implements_behaviour?(mod, Ash.Resource)` returns false for real resources — use `Ash.Resource.Info.resource?/1` (F-Spark).
- `Ash.Query.filter/2` is a macro and can't take runtime field lists — use `Ash.Query.filter_input/2`; case-insensitive contains via `Ash.CiString.new/1` (F67+).
- In a `use`-style macro that wraps Ash, `use Ash.Resource` must expand in `__using__` at the normal source position; deferring it to `@before_compile` breaks Ash's cross-module Spark verification under `--warnings-as-errors` (F50–F52).
- Igniter 0.8.3 AST comment insertion silently drops comments — never inject TODO comments into user files; use `Igniter.add_notice` with a copy-paste snippet instead (F76–F77).
- Snapshot JSON format and default FK/index naming (`"#{table}_#{attr}_fkey"`, `"#{table}_#{identity}_index"`) are undocumented AshPostgres internals with no compat promise — the tests reading real snapshots/names are the canary; expect breakage on AshPostgres upgrades (F17, F20, blueprint Risk 4).
- Never suppress or special-case a real diff to make a test pass; the clean-state zero-diff assertions (package harness AND spike0_crm) are the core regression gate.

## Foreign agent configs

`~/.codex/config.toml` and `~/.gemini/settings.json` exist on this machine. To import their MCP servers/commands/instructions into Claude Code, reply `/import` to scan (then `/import --yes=<digest>` to apply), or run `claude import` from a terminal.
