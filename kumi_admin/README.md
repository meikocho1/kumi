# kumi_admin

A LiveView admin shell derived from your `Kumi.App` declaration. Tables,
forms, search, `belongs_to` selects, child tables, dashboard metrics and
workflow stages — with no per-resource code on your side.

It is **not** an authentication system. kumi_admin is a post-login
experience that sits behind whatever your app already uses.

## Install

Not on Hex yet, so use a path dependency plus the installer:

```elixir
# mix.exs
{:kumi, path: "../kumi"},
{:kumi_admin, path: "../kumi_admin"}
```

```bash
mix deps.get
mix kumi_admin.install
```

The installer composes `mix kumi.install` (which generates
`lib/<app>/app.ex` — your `use Kumi.App` declaration — and an `<App>.Core`
domain registered in `:ash_domains`) and then mounts the admin into your
Phoenix router. When it can confirm an `ash_authentication_phoenix`-style
`LiveUserAuth` hook it wires the actor automatically; otherwise it prints
the exact snippet to add rather than guessing.

## Mounting by hand

```elixir
import KumiAdmin.Router

scope "/", MyAppWeb do
  pipe_through :browser

  kumi_admin "/admin",
    app: MyApp.App,
    on_mount: [{MyAppWeb.LiveUserAuth, :current_user}]
end
```

Options (see `KumiAdmin.Router` for the full list):

| Option | Default | What it does |
|---|---|---|
| `:app` | — | **Required.** The `Kumi.App` module to render. |
| `:on_mount` | `[]` | Hooks run before every admin LiveView. Populate whatever assign `:actor` reads — kumi_admin authenticates nobody itself. |
| `:actor` | `{KumiAdmin.Actor, :from_current_user}` | `{Module, :function}` resolving the Ash actor from the mounted socket. |
| `:sign_in_path` / `:sign_out_path` / `:register_path` | `/sign-in`, `/sign-out`, `/register` | Point these at your app's real routes. kumi_admin implements none of them. |
| `:user_resource` | `nil` | When set, an actor-less mount redirects to `:register_path` instead of `:sign_in_path` if this resource has zero records — "create the first user" onboarding. |
| `:live_session_name` | `:kumi_admin` | — |

## Two things that will bite you

**Every managed resource needs a single primary key named `:id`.** The
generic index/show/form LiveViews sort, link and look up records by that
name unconditionally (`Ash.Query.sort(:id)`). A composite or
differently-named primary key is rejected at compile time by a `Kumi.App`
verifier.

**No actor means no shell.** Every LiveView calls `KumiAdmin.Gate.check/2`
right after resolving the session; an actor-less visit redirects rather
than rendering. With an actor but restrictive policies, a
policy-protected resource legitimately comes back empty — the shell
renders that honestly ("No records visible to you.") instead of crashing,
and New/Edit/Delete buttons are gated by `Ash.can?`.

Actor handoff does not clobber your session: kumi_admin reads the full
Plug session and adds its own two keys, so what your `on_mount` hooks
need (e.g. `ash_authentication_phoenix`'s `user_token`) is still there.

## Uploads

If [`kumi_storage`](../kumi_storage/) is installed, image fields render as
uploads automatically. kumi_admin does **not** depend on kumi_storage — it
detects the generated Attachment resource through two marker functions
(`__kumi_attachment__/0`, `__kumi_attachment_url__/1`) and nothing else.

## Dependency contract

kumi_admin's deps are `kumi`, `phoenix`, `phoenix_live_view`, `ash_phoenix`
(plus optional `igniter` for the installer). That list is deliberate and
part of the architecture: a PR adding a dependency here needs to argue the
case first. Pure derivation logic (`Columns`, `FormFields`, `Search`,
`StageCounts`) is unit-tested in this package; LiveView behaviour is
tested against a real host app.

## Walkthrough

[`kumi/guides/mini-crm.md`](../kumi/guides/mini-crm.md) builds a CRM from
scratch — resources, admin, pipeline, dashboard. Every command in it was
executed.

## Development

```bash
mix deps.get
mix test
```

No database required — this package's tests are pure.

## Part of the Kumi project

> Ash helps you model your application. Kumi helps you ship it as a product.

See the [root README](../README.md) for the other packages and
[CONTRIBUTING.md](../CONTRIBUTING.md) for setup and what a reviewer looks
for.

## License

MIT — see [`LICENSE`](LICENSE).
