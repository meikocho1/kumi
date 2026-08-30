# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

All four packages in this repository share one version number and are
released together; see `RELEASING.md`.

## [Unreleased]

Nothing has been released yet — there are no tags, and every package's
`mix.exs` still reads `0.1.0`. The entries below are what the first
release will contain, reconstructed from the commit history. On the first
tag they collapse into that version's section.

### Added

**`kumi` — the plan engine**

- `mix kumi.plan` compares the Ash resources in your code against a
  **live** Postgres database and prints a desired-vs-actual diff. This is
  a different question from the one `mix ash.codegen` answers
  (code vs. snapshot), so it sees manual database drift that codegen
  cannot. `--check` gives an exit code for scripts, `--verbose` explains
  each operation, `--app` scopes the comparison to one declared app's
  tables.
- Safety classification for every proposed operation: anything that
  deletes data is DANGEROUS, constraint tightening and rename guesses are
  REVIEW, pure additions are SAFE. Unknown type pairs fail closed. Rename
  detection runs before classification so a dropped-and-re-added column
  is recognised as a rename rather than reported as data loss.
- `--probe` (opt-in) attaches read-only row-count findings that annotate
  operations without changing their classification, so `--check` exit
  codes never depend on live data.
- Timestamp precision drift detection (a `utc_datetime` column that is
  actually `timestamp(6)` in the database, and the reverse).
- `mix kumi.apply` repairs SAFE drift in development. Four independent
  gates: the operation must be classified SAFE, must be on an explicit
  allowlist, must render to exact SQL, and must not carry a default or
  precision change. It runs in one transaction, re-introspects afterwards
  to verify the result, and refuses to run outside `MIX_ENV=dev`.
- Fix hints: each diff operation carries a remediation line, favouring
  "add it to your code" over "drop it from the database".
- `Kumi.App`, a Spark DSL for application-level intent — title,
  the list of resources, admin navigation, dashboard metrics
  (`count`/`sum`), and workflow stages. It deliberately does not
  duplicate Ash's own domain DSL. Compile-time verifiers reject
  non-Ash resources, navigation entries outside the declared resource
  list, metrics over missing or non-public fields, and workflow stages
  outside an attribute's `one_of` constraint.
- `Kumi.Resource`, a shorthand that expands to a standard Ash resource,
  plus `mix kumi.expand` to print exactly what it compiles to. A test
  asserts the printed source and the compiled definition agree.
- `mix kumi.report`, a validation harness that runs format, compile,
  test, `ash.codegen --check` and the plan, then emits a single verdict
  (human-readable or `--json`).
- `mix kumi.install`, an Igniter installer that generates the app module
  and a `Core` domain and registers it.
- A guide to the Ash/Spark/AshPostgres/Igniter behaviours that cost real
  debugging time while building all of the above (`kumi/guides/`).

**`kumi_admin` — the admin**

- A LiveView admin whose sidebar, tables, forms, search and dashboard are
  derived from the App DSL, with no per-resource host code.
- Index, detail, new, edit and delete for every declared resource, with
  `belongs_to` selects, `has_many` child tables one level deep, and
  cross-field search.
- New/Edit/Delete buttons gated by `Ash.can?`. Policy-forbidden reads
  render an honest empty state instead of crashing.
- No authentication of its own: the router macro takes the host
  application's `on_mount` hooks and actor function, so the admin sits
  behind whatever the host already uses. First-run onboarding redirects to
  registration when the configured user resource has no rows yet.
- Dashboard metrics and workflow stage counts computed from real data,
  degrading to a "no access" state per widget rather than failing the
  page.
- Components organised as atoms / molecules / organisms, with a
  token-based default theme.
- Upload rendering driven purely by a marker contract, so the admin gains
  no dependency on the storage package.

**`kumi_storage` — uploads**

- `mix kumi_storage.install` generates a plain Ash `Attachment` resource
  with an `:upload` action, configures a local backend, and mounts a plug
  that serves stored files by generated key.
- A backend behaviour so other storage targets can be added, with size
  and content-type validation and path-traversal rejection in the local
  implementation.
- `:image` fields in the shorthand DSL expand to a relationship to the
  generated resource.

**`kumi` — sign-in providers**

- `mix kumi.gen.auth google|github|oidc` generates an OAuth2 sign-in
  strategy on your user resource. `mix ash_authentication.add_strategy`
  covers `password`, `magic_link` and `api_key`; the OAuth2 providers are
  hand-written DSL upstream, and this writes those same pieces as ordinary
  Ash source — the `UserIdentity` resource, the strategy block, a
  `register_with_<provider>` upsert action, and `secret_for/4` clauses
  that read credentials from application env.
- Two parts of the generated action are detected from your resource rather
  than assumed: without a unique identity it generates a plain create
  instead of DSL that will not compile, and `confirmed_at` is only set
  when that attribute exists.
- The provider console's redirect URI, the config values, and making
  `hashed_password` nullable are printed as instructions, never guessed
  at — no credential is written into source.

**`kumi_new` — the generator**

- `mix kumi.new my_app` goes from nothing to a running application in one
  command: project generation, dependency resolution, installers,
  database setup, and a themed starting page.
- Module selection at generation time, so you choose which optional
  modules (for example storage) the new project starts with.
- `--auth-strategy` selects the new project's sign-in methods, mixing the
  two generators freely: `password`, `magic_link`, `api_key` go to
  `ash_authentication`'s installer, `google` and `github` to
  `mix kumi.gen.auth` once the user resource exists. Values neither tool
  can generate are rejected before generation starts rather than failing
  part-way through.
- The generated sign-in page styles OAuth provider buttons to match the
  rest of the page, so adding Google or GitHub by hand does not leave an
  off-brand button behind.
- No runtime dependencies, so it stays installable as a Mix archive.

**Packaging**

- MIT licensed. `LICENSE` at the repository root and in each package.
- All four packages carry Hex metadata and produce a valid tarball
  (`mix hex.build`). `kumi_admin` and `kumi_storage` swap their path
  dependency on `kumi` for a version requirement when `KUMI_PUBLISH` is
  set; `kumi_new` stays dependency-free so it remains installable as a
  Mix archive.

### Fixed

Bugs found and fixed during development, listed because each one is a
trap worth knowing about:

- `mix kumi.plan` crashed outright on parameterized column types such as
  pgvector's `vector(1536)`, instead of failing closed. Unmapped type
  shapes now surface as an unrecognised change and are classified
  DANGEROUS.
- The admin shipped its stylesheet as literal, uninterpolated text
  because HEEx disables `{...}` interpolation inside `<style>` — every
  test passed and the page rendered completely unstyled.
- Foreign-key columns rendered as full untruncated UUIDs, and child
  tables on a detail page included the foreign key pointing back at the
  record you were already looking at.
