# Adding a JSON API to a Kumi App

Kumi is integration-first, not headless-first: for a Phoenix/LiveView app the
fastest, safest place for the frontend is the same app kumi_admin lives in
(see `kumi/guides/frontend.md`). But sometimes you genuinely need a JSON API
— a mobile client, a third-party integration, a headless frontend team. This
guide is that path. Every command and response below was actually run
against a real app and a real database — nothing here is hypothetical.

**The policy this guide implements** (blueprint §9): Kumi does not build an
API layer. `AshJsonApi` is already a complete, proven library — wrapping it
would violate the "no thin wrappers" rule the same way a Kumi ORM would
violate D2. Kumi's job is to show the path, honestly, including where it's
rougher than the happy path suggests.

**What you'll build**: a `Contact` resource and a `Deal` resource (`Deal
belongs_to Contact`, `Contact has_many Deal`), both exposed over JSON:API,
with a working `?include=` in both directions and one gotcha you will
absolutely hit resolved for you: JSON:API's own content type gets rejected by
a stock Phoenix `:accepts` pipeline.

## Step 0 — The honest framing: shorthand doesn't do this, and that's intentional

`Kumi.Resource` (the shorthand DSL) has no `json_api` option. This isn't an
oversight — check the source yourself, `kumi/lib/kumi/resource.ex` says so
directly in its moduledoc:

> **Escape hatch**: need calculations, aggregates, policies, custom actions,
> or anything else beyond the default four actions? Write the Ash resource
> directly — start from `mix kumi.expand MyApp.Customer`'s output and edit
> it.

`Kumi.Resource.Codegen.generate/3` (the single function both the macro and
`mix kumi.expand` call — see `CLAUDE.md`'s D1) has no code path that emits a
`json_api do ... end` block, an `extensions:` list, or anything AshJsonApi-
related. This isn't a bug to work around; it's D1 "Show Ash" in its purest
form: the shorthand covers the common 90%, and the moment you need something
it doesn't cover, you take the exact Ash source it already compiles to and
keep editing by hand. There's no fork, no wrapper, no Kumi-specific JSON API
convention layered on top.

Concretely, that means: build `Contact` with the shorthand first (like any
other Kumi resource), print what it expands to, then convert it to a
hand-written `Ash.Resource` and add `AshJsonApi.Resource` the same way you'd
add it to a resource you'd written from scratch.

```elixir
# lib/apiguide/core/contact.ex — shorthand, step one
defmodule Apiguide.Core.Contact do
  use Kumi.Resource,
    domain: Apiguide.Core,
    repo: Apiguide.Repo,
    table: "contacts"

  fields do
    field :name, :string, required: true
    field :email, :email
    has_many :deals, Apiguide.Core.Deal
  end
end
```

```
$ mix kumi.expand Apiguide.Core.Contact
defmodule Apiguide.Core.Contact do
  use Ash.Resource,
    domain: Apiguide.Core,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("contacts")
    repo(Apiguide.Repo)
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

    timestamps()
  end

  relationships do
    has_many(:deals, Apiguide.Core.Deal)
  end
end
```

That output is a completely ordinary Ash resource — nothing about it is
Kumi-flavored. Everything from here is plain Ash plus AshJsonApi, applied to
that exact source.

## Step 1 — Add the deps

```elixir
# mix.exs
{:ash_json_api, "~> 1.0"},
{:open_api_spex, "~> 3.0"},
```

```bash
mix deps.get
```

## Step 2 — Convert Contact to plain Ash and add `AshJsonApi.Resource`

Take the `mix kumi.expand` output verbatim and add four things: the
extension, the `json_api` block (with an explicit `includes` list — this
part is easy to skip and then wonder why `?include=` 400s), and
`public?: true` on the `has_many :deals` relationship (the expand output
leaves relationships at their default visibility; the API layer needs them
public to expose them at all):

```elixir
# lib/apiguide/core/contact.ex — now plain Ash, the escape hatch
defmodule Apiguide.Core.Contact do
  use Ash.Resource,
    domain: Apiguide.Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "contacts"
    repo Apiguide.Repo
  end

  json_api do
    type "contact"
    # `deals: [:contact]` — not `[:deals]` — is what makes the *nested*
    # path `?include=deals.contact` valid too (Step 6). `includes` is a
    # keyword list of "paths reachable from this resource", declared once,
    # here, not something each resource along the chain repeats.
    includes(deals: [:contact])

    routes do
      base("/contacts")

      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
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

    timestamps()
  end

  relationships do
    has_many :deals, Apiguide.Core.Deal, public?: true
  end
end
```

`Deal` is written the same way — plain Ash from the start this time, exactly
the pattern `kumi/guides/mini-crm.md` uses for its own `Deal` (a `belongs_to`
plus a closed `stage` enum is beyond the shorthand's `:select` sugar anyway):

```elixir
# lib/apiguide/core/deal.ex
defmodule Apiguide.Core.Deal do
  use Ash.Resource,
    domain: Apiguide.Core,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "deals"
    repo Apiguide.Repo
  end

  json_api do
    type "deal"
    includes([:contact])

    routes do
      base("/deals")

      get(:read)
      index :read
      post(:create)
      patch(:update)
      delete(:destroy)
    end
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
    belongs_to :contact, Apiguide.Core.Contact do
      public? true
    end
  end
end
```

## Step 3 — Domain-level wiring: the part that fails silently at compile time

The domain needs `extensions: [AshJsonApi.Domain]`. Without it, everything
above still **compiles cleanly** — the failure only shows up as a 500 the
first time you make an actual request (`UndefinedFunctionError:
Apiguide.Core.json_api_match_route/2 is undefined`), because that function is
generated by a domain-level Spark transformer, not a resource-level one:

```elixir
# lib/apiguide/core.ex
defmodule Apiguide.Core do
  use Ash.Domain,
    otp_app: :apiguide,
    extensions: [AshJsonApi.Domain]

  resources do
    resource Apiguide.Core.Contact
    resource Apiguide.Core.Deal
  end
end
```

Mount the router (`AshJsonApi.Router` takes the list of domains and derives
every resource's declared routes automatically — nothing to repeat here):

```elixir
# lib/apiguide_web/ash_json_api_router.ex
defmodule ApiguideWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Apiguide.Core],
    open_api: "/open_api"
end
```

```elixir
# lib/apiguide_web/router.ex
scope "/api/json" do
  pipe_through [:api]

  forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
    path: "/api/json/open_api",
    default_model_expand_depth: 4

  forward "/", ApiguideWeb.AshJsonApiRouter
end
```

and add `AshJsonApi.Plug.Parser` to the endpoint's body parser (it decodes
JSON:API's `{"data": {"type": ..., "attributes": ...}}` envelope):

```elixir
# lib/apiguide_web/endpoint.ex
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json, AshJsonApi.Plug.Parser],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
```

## Step 4 — The trap: `:accepts, ["json"]` rejects JSON:API's own content type

A generated `kumi.new`/`phx.new` app's `:api` pipeline is just
`plug :accepts, ["json"]`. Curl it with the header JSON:API actually
requires and you get a **406**, not a working API:

```
$ curl -w '\nHTTP_STATUS:%{http_code}\n' -H "Accept: application/vnd.api+json" \
    http://localhost:4010/api/json/contacts
...
** (Phoenix.NotAcceptableError) no supported media type in accept header.
Expected one of ["json"] but got the following formats:
  * "application/vnd.api+json" with extensions: ["json-api"]
HTTP_STATUS:406
```

`application/vnd.api+json` isn't a MIME type Phoenix's `:accepts` plug
recognizes out of the box. Register it as an alias for `"json"` (add this
before `AshJsonApi.Plug.Parser` will do any good, and before your first
request — a stale `:mime` build won't pick up the new mapping until it's
rebuilt):

```elixir
# config/config.exs
config :mime,
  extensions: %{"json" => "application/vnd.api+json"},
  types: %{"application/vnd.api+json" => ["json"]}
```

```bash
mix deps.clean --build mime
```

With that in place, `curl -H "Accept: application/vnd.api+json" ...` returns
a real JSON:API response instead of 406.

## Step 5 — Migrate and start the server

```bash
MIX_ENV=dev mix ash.codegen add_contacts_and_deals
mix ecto.migrate
mix phx.server
```

## Step 6 — Every endpoint, actually curled

**Collection GET** (empty database):

```
$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -H "Accept: application/vnd.api+json" \
    http://localhost:4010/api/json/contacts
{"data":[],"links":{"self":"http://localhost:4010/api/json/contacts"},"meta":{},"jsonapi":{"version":"1.0"}}
HTTP_STATUS:200
```

**POST create a contact:**

```
$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -X POST \
    -H "Content-Type: application/vnd.api+json" -H "Accept: application/vnd.api+json" \
    -d '{"data":{"type":"contact","attributes":{"name":"Ada Lovelace","email":"ada@example.com"}}}' \
    http://localhost:4010/api/json/contacts
{"data":{"attributes":{"email":"ada@example.com","name":"Ada Lovelace"},"id":"640cc973-9937-4562-ba5d-7dbd931c28ec","links":{},"meta":{},"type":"contact","relationships":{"deals":{"links":{},"meta":{}}}},"links":{"self":"http://localhost:4010/api/json/contacts"},"meta":{},"jsonapi":{"version":"1.0"}}
HTTP_STATUS:201
```

**POST create a deal for that contact — via `relationships` first, which
fails, then via `attributes.contact_id`, which works** (see Step 7 below for
why):

```
$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -X POST \
    -H "Content-Type: application/vnd.api+json" -H "Accept: application/vnd.api+json" \
    -d '{"data":{"type":"deal","attributes":{"amount":"1200.00","stage":"qualified"},"relationships":{"contact":{"data":{"type":"contact","id":"640cc973-..."}}}}}' \
    http://localhost:4010/api/json/deals
** (Protocol.UndefinedError) protocol Enumerable not implemented for Atom
...
HTTP_STATUS:500

$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -X POST \
    -H "Content-Type: application/vnd.api+json" -H "Accept: application/vnd.api+json" \
    -d '{"data":{"type":"deal","attributes":{"amount":"1200.00","stage":"qualified","contact_id":"640cc973-9937-4562-ba5d-7dbd931c28ec"}}}' \
    http://localhost:4010/api/json/deals
{"data":{"attributes":{"amount":"1200.00","contact_id":"640cc973-9937-4562-ba5d-7dbd931c28ec","stage":"qualified"},"id":"1eaf50a0-b7b3-4050-b692-426a01883b8a","links":{},"meta":{},"type":"deal","relationships":{"contact":{"links":{},"meta":{}}}},"links":{"self":"http://localhost:4010/api/json/deals"},"meta":{},"jsonapi":{"version":"1.0"}}
HTTP_STATUS:201
```

**Single-resource GET:**

```
$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -H "Accept: application/vnd.api+json" \
    http://localhost:4010/api/json/deals/1eaf50a0-b7b3-4050-b692-426a01883b8a
{"data":{"attributes":{"amount":"1200.00","contact_id":"640cc973-9937-4562-ba5d-7dbd931c28ec","stage":"qualified"},"id":"1eaf50a0-b7b3-4050-b692-426a01883b8a","links":{},"meta":{},"type":"deal","relationships":{"contact":{"links":{},"meta":{}}}},"links":{"self":"http://localhost:4010/api/json/deals/1eaf50a0-b7b3-4050-b692-426a01883b8a"},"meta":{},"jsonapi":{"version":"1.0"}}
HTTP_STATUS:200
```

**404 for a missing record** (Ash's own error, formatted by AshJsonApi):

```
$ curl -s -w '\nHTTP_STATUS:%{http_code}\n' -H "Accept: application/vnd.api+json" \
    http://localhost:4010/api/json/contacts/00000000-0000-0000-0000-000000000000
{"errors":[{"code":"not_found","id":"be945901-...","meta":{},"status":"404","title":"Entity Not Found","detail":"No contact record found with `id: 00000000-0000-0000-0000-000000000000`"}],"jsonapi":{"version":"1.0"}}
HTTP_STATUS:404
```

**`?include=` — relationship depth, both directions.** This is JSON:API's
answer to Payload's "depth" parameter: one query, one round trip, the related
resource riding along in the same response's `included` array.

```
$ curl -s -H "Accept: application/vnd.api+json" \
    "http://localhost:4010/api/json/deals/1eaf50a0-b7b3-4050-b692-426a01883b8a?include=contact"
{"data":{...,"relationships":{"contact":{"data":{"id":"640cc973-...","type":"contact"},...}}},
 "included":[{"attributes":{"email":"ada@example.com","name":"Ada Lovelace"},"id":"640cc973-...","type":"contact",...}],
 "jsonapi":{"version":"1.0"}}
HTTP_STATUS:200

$ curl -s -H "Accept: application/vnd.api+json" \
    "http://localhost:4010/api/json/contacts/640cc973-9937-4562-ba5d-7dbd931c28ec?include=deals"
{"data":{...,"relationships":{"deals":{"data":[{"id":"1eaf50a0-...","type":"deal"}],...}}},
 "included":[{"attributes":{"amount":"1200.00","stage":"qualified",...},"id":"1eaf50a0-...","type":"deal",...}],
 "jsonapi":{"version":"1.0"}}
HTTP_STATUS:200
```

Both directions actually returned the related record inline. **Multi-hop
(`?include=deals.contact`) also actually works** — but only once the include
path is declared as a *nested* keyword list on the resource where the path
starts (Step 2's `includes(deals: [:contact])` on `Contact`), not by having
`Deal` separately declare anything:

```
$ curl -s -H "Accept: application/vnd.api+json" \
    "http://localhost:4010/api/json/contacts/640cc973-9937-4562-ba5d-7dbd931c28ec?include=deals.contact"
{"data":{...},
 "included":[
   {"type":"contact","id":"640cc973-...",...},
   {"type":"deal","id":"1eaf50a0-...","relationships":{"contact":{"data":{"id":"640cc973-...","type":"contact"}}},...}
 ],
 "jsonapi":{"version":"1.0"}}
HTTP_STATUS:200
```

Before adding the nested form, the flat `includes([:deals])` from Step 2's
first draft returned a **400** for this exact same URL
(`{"code":"invalid_includes","detail":"Invalid includes:
[[\"deals\",\"contact\"]]"}`) — the real answer to "how deep can I go" is: as
deep as the *root* resource's `includes` keyword list nests, not something
each resource along the path declares independently.

**OpenAPI schema**, generated for free from the same `json_api` blocks (no
YAML to hand-write):

```
$ curl -s -o /dev/null -w 'HTTP_STATUS:%{http_code}\n' http://localhost:4010/api/json/open_api
HTTP_STATUS:200
```

## Step 7 — Why the `relationships` POST failed (and stays that way here)

The default `create: :*` action (`defaults [:read, :destroy, create: :*,
update: :*]`, exactly what the shorthand also generates) accepts every
public **attribute** — and a `belongs_to`'s foreign key (`contact_id`) is
just a plain attribute (the same fact `ash-gotchas.md` already documents for
generic tooling). It does **not** automatically accept the relationship
*name* (`contact`) as an input, which is what JSON:API's `relationships`
write payload needs. Sending `relationships.contact` against an action that
doesn't accept it raises `Ash.Error.Invalid.NoSuchInput` — and in
`ash_json_api` 1.7.1 that specific error's own formatter has a bug
(`Protocol.UndefinedError: Enumerable not implemented for Atom`, filed
upstream-worthy, not something this guide works around), so what you see is
a raw 500 instead of a clean 4xx. **Workaround used above**: send the foreign
key directly under `attributes` (`attributes.contact_id`), which the default
action already accepts. **The real fix**, if you want `relationships` writes
to work as JSON:API intends, is a custom `create` action whose `accept`
includes the relationship name (or a `change manage_relationship/3`) —
deliberately not built here; it's a per-resource decision, not something a
generic guide should default for you.

## Auth: out of scope for this guide, not silently skipped

None of the above has any authorization on it — `Contact` and `Deal` have no
`policies` block and no `authorizers:`, so every request above worked
unauthenticated. That's a deliberate simplification for a guide about
wiring, not a recommendation. `kumi.new`'s generated `:api` pipeline already
has the plumbing for real auth (`plug :load_from_bearer` +
`plug :set_actor, :user`, wired by `AshAuthentication.Phoenix.Router`) — it
resolves a bearer token into `conn.assigns[:current_user]` and sets it as the
Ash actor, exactly the value a `policy` block would check with
`actor_present()` or similar. What this guide does **not** show: issuing a
bearer token to an API client, or adding `authorizers: [Ash.Policy.Authorizer]`
+ a real `policies do ... end` block to lock these resources down. For that,
see [AshAuthentication's docs](https://hexdocs.pm/ash_authentication) (token
strategy) and Ash's own policy guide — both are complete, standard Ash
mechanisms with nothing Kumi-specific layered on top, consistent with D1.
**If you copy this guide's resources into a real app, add policies before
you expose them publicly** — as written, they're wide open.

## Where you still write glue code today

- **`includes` must be listed explicitly, and multi-hop paths nest on the
  *root* resource, not on each resource along the chain.** Forgetting it
  doesn't silently no-op — `?include=deals` against a resource that hasn't
  declared `includes([:deals])` returns a `400 invalid_includes`, even
  though the relationship itself works fine for direct reads. And
  `?include=deals.contact` needs `includes(deals: [:contact])` on `Contact`
  specifically — declaring `includes([:contact])` separately on `Deal` does
  nothing for this path; it isn't a per-hop declaration, it's a path tree
  declared once at the entry point.
- **Writing a to-one relationship via JSON:API's `relationships` block needs
  a custom action.** The default `create: :*` action only accepts attributes;
  `attributes.contact_id` works today, `relationships.contact` needs
  `accept` (or `manage_relationship`) added by hand per resource (Step 7).
- **The domain needs `extensions: [AshJsonApi.Domain]`, and forgetting it
  fails at request time, not compile time.** Everything compiles cleanly
  without it; the first real HTTP request 500s with an
  `UndefinedFunctionError` on a function (`json_api_match_route/2`) that
  only a domain-level Spark transformer generates. There is no compile-time
  signal that you forgot this.
- **The stock `:accepts, ["json"]` pipeline doesn't recognize
  `application/vnd.api+json`.** Every JSON:API client sends that content
  type by spec; without the `:mime` config in Step 4, every request 406s
  before it reaches AshJsonApi at all.
- **No auth is wired up in this guide, on purpose** (see the Auth section
  above) — the bearer-token plumbing already exists in a `kumi.new` app, but
  turning it into an enforced policy is a per-resource decision this guide
  doesn't make for you.
- **No pagination, filtering, or sorting is demonstrated.** AshJsonApi
  supports all three (`page[limit]`/`page[offset]`, `filter[...]`,
  `sort=...`) the same way it supports `include` — declared per action —
  but none of it was exercised here; treat it as the natural next step, not
  as unsupported.
