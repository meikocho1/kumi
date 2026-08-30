# Building a Mini CRM with Kumi

This is a from-scratch walkthrough: generate a Phoenix+Ash app, add two
resources, wire them into an admin UI with a sales pipeline and a dashboard,
then exercise Kumi's schema-drift loop against a real database. Every command below
was actually run, and every output is what it printed — nothing here is
hypothetical.

**What Kumi is, in three lines**: Kumi is a thin layer over Ash. The
`Kumi.Resource` shorthand compiles to a real, inspectable Ash resource (you
can always print exactly what it expands to); `Kumi.App` declares which
resources belong to your product and drives an admin UI and dashboards from
that declaration; `mix kumi.plan` diffs your Ash resources against the *live*
database and tells you what drifted. Kumi never hides Ash — writing plain Ash
directly is always the supported escape hatch, not a fallback.

**What you'll build**: a CRM with a `Contact` resource (via the Kumi
shorthand) and a `Deal` resource (in plain Ash, on purpose), a sales pipeline
workflow, an overview dashboard with two metrics, and a live look at how
`mix kumi.plan` / `mix kumi.apply` handle someone dropping a column by hand.

This guide assumes you've cloned Kumi and are creating your app as a sibling
project a couple of directories over — adjust `--kumi-path` to wherever your
checkout actually lives; it just needs to point at the `kumi` package
directory.

## Prerequisites

You need Postgres reachable. Kumi isn't published to Hex yet (same caveat
as the main README), so you install its generator archive from source
once:

```bash
mix archive.install hex igniter_new
mix archive.install hex phx_new
(cd ../../kumi_new && mix archive.build && mix archive.install)  # not on Hex yet
```

## Step 1 — Generate the app

```bash
mix kumi.new mini_crm --kumi-path ../.. --db-port 5434
```

This runs `mix igniter.new` with Ash + Phoenix + Ash Authentication, adds
Kumi and kumi_admin as dependencies, mounts the admin UI at `/kumi-admin`,
generates a `MiniCrm.App` skeleton and a `MiniCrm.Core` domain (registered in
`:ash_domains` alongside the auth domain), and runs `mix ash.setup` (creates
the dev database, migrates auth tables). All Kumi/Phoenix work; nothing here
is hand-written yet.

`lib/mini_crm/app.ex` comes out as:

```elixir
defmodule MiniCrm.App do
  use Kumi.App

  app do
    name :mini_crm
    title("Mini Crm")
  end

  resources do
    # List the Ash resources that make up this app, e.g.:
    #   resource MiniCrm.MyResource
  end
end
```

`lib/mini_crm/core.ex` comes out as:

```elixir
defmodule MiniCrm.Core do
  use Ash.Domain,
    otp_app: :mini_crm

  resources do
  end
end
```

## Step 2 — Contact, via the Kumi.Resource shorthand

`kumi.new` already generated `MiniCrm.Core` — register your resources there,
no hand-written domain module needed:

```elixir
# lib/mini_crm/core/contact.ex
defmodule MiniCrm.Core.Contact do
  use Kumi.Resource,
    domain: MiniCrm.Core,
    repo: MiniCrm.Repo,
    table: "contacts"

  fields do
    field :name, :string, required: true
    field :email, :email
    field :phone, :string
    has_many :deals, MiniCrm.Core.Deal
  end
end
```

```elixir
# lib/mini_crm/core.ex
defmodule MiniCrm.Core do
  use Ash.Domain, otp_app: :mini_crm

  resources do
    resource MiniCrm.Core.Contact
    resource MiniCrm.Core.Deal
  end
end
```

`:ash_domains` in config is already set — `kumi.install` appended `MiniCrm.Core`
to the list next to the auth domain, so there's nothing to edit here:

```elixir
# config/config.exs
config :mini_crm,
  ash_domains: [MiniCrm.Core, MiniCrm.Accounts]
```

**Show Ash.** Kumi's shorthand is sugar, never a black box —
`mix kumi.expand` prints exactly what it compiles to:

```
$ mix kumi.expand MiniCrm.Core.Contact
defmodule MiniCrm.Core.Contact do
  use Ash.Resource,
    domain: MiniCrm.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("contacts")
    repo(MiniCrm.Repo)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :email, :string do
      public?(true)
      constraints(match: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    end

    attribute :phone, :string do
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_many(:deals, MiniCrm.Core.Deal)
  end
end
```

Everything the shorthand did: a UUID primary key, default CRUD actions, three
attributes with a `required`/email-format constraint, and the relationship.
There's no `:phone` field type — it's just `:string`; the shorthand's type
list is intentionally small (`string`, `text`, `integer`, `decimal`,
`boolean`, `date`, `datetime`, `email`, `select`), not a full Ash type
mirror.

## Step 3 — Deal, in plain Ash (the escape hatch, on purpose)

`Deal` needs a `stage` attribute with a default and a closed set of allowed
values, plus a `belongs_to`. The shorthand's `:select` type *can* express
`one_of` + default, but this guide writes `Deal` in plain Ash deliberately —
this is the supported path for anything the shorthand doesn't cover, not a
workaround:

```elixir
# lib/mini_crm/core/deal.ex
defmodule MiniCrm.Core.Deal do
  use Ash.Resource,
    domain: MiniCrm.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "deals"
    repo MiniCrm.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :amount, :decimal do
      allow_nil? false
      public? true
    end

    attribute :stage, :atom do
      public? true
      default :lead
      constraints one_of: [:lead, :qualified, :won, :lost]
    end

    timestamps()
  end

  relationships do
    belongs_to :contact, MiniCrm.Core.Contact do
      public? true
    end
  end
end
```

Kumi did nothing here — this is a normal `Ash.Resource`. It only needs to be
listed in `MiniCrm.Core`'s `resources do ... end` (already done above) and in
`MiniCrm.App`'s `resources` block (next step) to show up in the admin UI.

## Step 4 — Generate the migration, register the app, add a workflow and dashboard

```bash
MIX_ENV=dev mix ash.codegen add_crm_resources
mix ecto.migrate
```

`ash.codegen` printed a "this migration includes destructive operations"
warning even though this is a pure table-creation migration — it's triggered
by the generated `down/0`, which does contain `drop table`. Worth knowing so
it doesn't read as a red flag on every fresh resource.

Now wire `Contact` and `Deal` into the app declaration, add navigation, a
sales-pipeline workflow keyed on `Deal.stage`, and a dashboard with two
metrics:

```elixir
# lib/mini_crm/app.ex
defmodule MiniCrm.App do
  use Kumi.App

  app do
    name :mini_crm
    title("Mini Crm")
  end

  resources do
    resource MiniCrm.Core.Contact
    resource MiniCrm.Core.Deal
  end

  admin do
    navigation [MiniCrm.Core.Contact, MiniCrm.Core.Deal]
  end

  workflow :sales_pipeline,
    resource: MiniCrm.Core.Deal,
    field: :stage,
    stages: [:lead, :qualified, :won, :lost]

  dashboard :overview do
    metric :deal_count, resource: MiniCrm.Core.Deal
    metric :pipeline_value, resource: MiniCrm.Core.Deal, kind: :sum, field: :amount
  end
end
```

`workflow` and `dashboard` are top-level entries (not nested inside `app do`
or `resources do`) — `mix format` will reformat the multi-line `workflow`
call into parens-wrapped style; run it once before your first
`mix kumi.report` or the format check fails on your own hand-written DSL,
not on generated code.

## Step 5 — Verify headlessly (no `phx.server` needed)

```bash
$ mix test
Running ExUnit with seed: ..., max_cases: 16
.....
Finished in 0.06 seconds
Result: 5 passed

$ mix kumi.report --skip-tests
✓ format   all files formatted
✓ compile  compiled cleanly (no warnings)
○ test     skipped (by flag)
✓ codegen  up to date (no pending migrations)
✓ plan     clean — database matches application definition

Verdict: ready — Ready for PR

$ mix phx.routes | grep kumi-admin
  GET  /kumi-admin                      KumiAdmin.DashboardLive :dashboard
  GET  /kumi-admin/:resource            KumiAdmin.ResourceIndexLive :index
  GET  /kumi-admin/:resource/new        KumiAdmin.ResourceFormLive :new
  GET  /kumi-admin/:resource/:id        KumiAdmin.ResourceShowLive :show
  GET  /kumi-admin/:resource/:id/edit   KumiAdmin.ResourceFormLive :edit
```

Five routes, a clean report, a green test suite — proof the app works
without ever booting a server or opening a browser.

## Step 6 — The drift loop: plan, fix-hints, apply, plan again

Simulate someone hand-editing the database — drop a nullable column that
Kumi's schema says should exist:

```bash
psql -h localhost -p 5434 -U postgres -d mini_crm_dev \
  -c "ALTER TABLE contacts DROP COLUMN phone;"
```

`mix kumi.plan` catches it immediately:

```
$ mix kumi.plan
contacts:
  + column phone text  [SAFE: adds nullable column phone]

1 safe / 0 review / 0 dangerous
```

`--fix-hints` adds advisory remediation text — it never executes anything,
just tells you what to run:

```
$ mix kumi.plan --fix-hints
contacts:
  + column phone text  [SAFE: adds nullable column phone]
      fix: mix ash.codegen <name> && mix ash_postgres.migrate  (code ahead of DB)
      if codegen emits nothing, the DB drifted — apply manually: ALTER TABLE contacts ADD COLUMN phone text;
```

This is exactly the case `ash.codegen` cannot see (the DB fell *behind* what
code+snapshot already agree on, not ahead of it) — that's what
`mix kumi.apply` exists for:

```
$ mix kumi.apply --yes
  WILL RUN: :add_column — ALTER TABLE contacts ADD COLUMN phone text;
executed 1 / skipped 0 — verified: true

$ mix kumi.plan
No changes. Database matches application definition.
```

`kumi.apply` only ever runs operations classified `:safe`, on an explicit
allowlist, that render to exact SQL — `:review` and `:dangerous` operations
are printed with a reason and never executed, under any flag.

## Step 7 — An avatar field, via `kumi_storage`

Add the storage plugin the same way you added everything else — an
installer, composed on top of `kumi.install`:

```elixir
# mix.exs
{:kumi_storage, path: "../../kumi_storage"},
```

```bash
mix deps.get
mix kumi_storage.install --yes
```

```
Notices:

* Kumi Storage: created MiniCrm.Core.Attachment and registered it in
  MiniCrm.Core.
* Kumi Storage: mounted file serving at /uploads/:key in MiniCrmWeb.Router.
```

`MiniCrm.Core.Attachment` is a plain Ash resource (D1 — not a `Kumi.Resource`
shorthand), fully yours to read: a `:upload` create action that validates
size/content-type and calls the configured backend's `store/4`, and a
`__kumi_attachment_url__/1` function matching the `/uploads` forward the
installer just added to your router. Now the field line is exactly what
you'd expect from any other field type:

```elixir
field :avatar, :image, to: MiniCrm.Core.Attachment
```

```
$ mix kumi.expand MiniCrm.Core.Contact
defmodule MiniCrm.Core.Contact do
  use Ash.Resource,
    domain: MiniCrm.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("contacts")
    repo(MiniCrm.Repo)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :email, :string do
      public?(true)
      constraints(match: ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
    end

    attribute :phone, :string do
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :avatar, MiniCrm.Core.Attachment do
      public?(true)
    end

    has_many(:deals, MiniCrm.Core.Deal)
  end
end
```

Same shape as `:belongs_to` for any other resource — the `:image` type is
sugar for a `belongs_to` an Attachment, nothing more; `name`/`email`/`phone`
and the `deals` relationship are unchanged from Step 2. Migrate and verify —
`contacts` and `deals` already exist from Step 4, so this migration only
adds the `attachments` table and the new `avatar_id` column:

```bash
MIX_ENV=dev mix ash.codegen add_avatar
mix ecto.migrate
mix kumi.report --skip-tests
```

```
✓ format   all files formatted
✓ compile  compiled cleanly (no warnings)
○ test     skipped (by flag)
✓ codegen  up to date (no pending migrations)
✓ plan     clean — database matches application definition

Verdict: ready — Ready for PR
```

kumi_admin's generated form for `Contact` now has a real file input for
`Avatar` and shows a "Current file" link when editing a record that already
has one — no code written for either. It works via a marker contract, not a
new dependency: `kumi_admin` never imports `kumi_storage` (its deps stay
`kumi` + `phoenix` + `phoenix_live_view` + `ash_phoenix`); it just checks
whether a `belongs_to`'s destination module exports `__kumi_attachment__/0`,
and if so drives the upload through that resource's own `:upload` action and
reads the link back through its own `__kumi_attachment_url__/1`. Uploading a
new file always creates a new Attachment record and re-points the
relationship — the old one is not deleted (an intentional deferral, see
below), so replacing an avatar a few times does leave orphaned rows and
files behind.

## Where you still write glue code today

Building this CRM surfaced a short, concrete list of things Kumi doesn't
cover yet — this is the roadmap, not an apology:

- **Upload / attachment support** — previously the biggest gap and the most
  likely first plugin; now provided by `kumi_storage` (Step 7): `field
  :avatar, :image, to: ...` plus `mix kumi_storage.install` gets you a real
  file input in kumi_admin's generated forms, with zero new deps on
  kumi_admin's side. What's still deferred, deliberately: only a local
  filesystem backend ships (an S3 backend is a planned follow-up, not
  built yet); replacing an attachment leaves the old record and file as an
  orphan (no sweep job); and there's no thumbnail/resize pipeline — the
  form and detail page link to the original file only.
- **Domain scaffolding** — previously you had to hand-write a
  `use Ash.Domain` + `resources do ... end` module and a manual
  `ash_domains` config entry for every project; now `mix kumi.install`
  generates a default `<App>.Core` domain and registers it in
  `:ash_domains` for you (this guide's `MiniCrm.Core`), so you only write
  the resource modules themselves.
- **No phone-shaped field type.** `Kumi.Resource`'s type list stops at
  `string`/`text`/`integer`/`decimal`/`boolean`/`date`/`datetime`/`email`/
  `select` — a phone number is just a `:string`, with no format constraint
  offered out of the box.
- **`ash.codegen`'s destructive-operation warning fires on pure creates.**
  A brand-new table's migration triggers "includes destructive operations"
  because its generated `down/0` contains `drop table` — worth knowing so it
  doesn't read as a real warning on your first migration.
