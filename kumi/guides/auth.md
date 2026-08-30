# Authentication in a Kumi App

Kumi has **no authentication of its own**, by design. `kumi_admin` is a
post-login shell: it reads an actor out of the socket your app already
populated and gates every LiveView on it (`KumiAdmin.Gate`,
`KumiAdmin.Actor`). Authentication itself is
[`ash_authentication`](https://hexdocs.pm/ash_authentication) — a complete,
maintained library — and wrapping it would break the same "no thin
wrappers" rule that keeps Kumi out of the ORM and API business — the same
settled decision as D1 "Show Ash".

So this guide is not "Kumi's auth". It is: what `mix kumi.new` wires for
you, what it deliberately doesn't, and the exact path from there to
multiple sign-in providers and two-factor auth.

## What you get out of the box

```bash
mix kumi.new my_app --kumi-path /path/to/Kumi --db-port 5434
```

installs `ash_authentication` + `ash_authentication_phoenix` and generates
a `MyApp.Accounts.User` with the **password** strategy, a `Token`
resource, a `MyApp.Secrets` module, the `/sign-in` `/register` `/sign-out`
routes, and a `MyAppWeb.AuthOverrides` styled to match the admin shell.

Pick different strategies at generate time:

```bash
mix kumi.new my_app --auth-strategy password,magic_link --kumi-path ...
```

`--auth-strategy` accepts exactly `password`, `magic_link`, and `api_key`,
comma-separated. That list is not Kumi being conservative — it is the
complete set that `mix ash_authentication.add_strategy` can generate.
Anything else is rejected at argument-parse time rather than failing
halfway through a project generation.

Adding a strategy to an app that already exists is the same task, run
inside it:

```bash
mix ash_authentication.add_strategy magic_link
mix ash.codegen add_magic_link
mix ash.migrate
```

## Multiple providers: Google, GitHub, Apple, Slack, Auth0, OIDC

`ash_authentication` ships all of these
(`AshAuthentication.Strategy.Google` and siblings). **None of them has an
installer** — there is no `add_strategy google`. They are hand-written DSL
on your user resource, which is exactly the escape hatch D1 promises: the
resource is plain Ash, you edit it directly.

The upstream tutorials are authoritative and per-provider — read the one
for your provider rather than adapting another:

- [Google](https://hexdocs.pm/ash_authentication/google.html) ·
  [GitHub](https://hexdocs.pm/ash_authentication/github.html) ·
  [Apple](https://hexdocs.pm/ash_authentication/apple.html) ·
  [Slack](https://hexdocs.pm/ash_authentication/slack.html) ·
  [Auth0](https://hexdocs.pm/ash_authentication/auth0.html)
- Generic [OAuth2](https://hexdocs.pm/ash_authentication/AshAuthentication.Strategy.OAuth2.html)
  and [OIDC](https://hexdocs.pm/ash_authentication/AshAuthentication.Strategy.Oidc.html)
  for anything else (Microsoft Entra, Okta, Keycloak, your company's IdP).

The shape is the same for every one of them, and there are four moving
parts. Using Google as the example:

**1. A `UserIdentity` resource.** Every OAuth2 strategy needs one. It
stores the provider's `iss`/`sub` claims, which is the only stable way to
recognise a returning user — matching on email address is not safe.

```elixir
defmodule MyApp.Accounts.UserIdentity do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity],
    domain: MyApp.Accounts

  user_identity do
    user_resource MyApp.Accounts.User
  end

  postgres do
    table "user_identities"
    repo MyApp.Repo
  end
end
```

Register it in the domain, then `mix ash.codegen add_user_identities &&
mix ash.migrate`.

**2. The strategy block** on `MyApp.Accounts.User`:

```elixir
authentication do
  strategies do
    password :password do
      identity_field :email
    end

    google do
      client_id MyApp.Secrets
      redirect_uri MyApp.Secrets
      client_secret MyApp.Secrets
      identity_resource MyApp.Accounts.UserIdentity
    end
  end
end
```

Providers stack: add a `github do ... end` next to it and both buttons
appear. Secrets go through your generated `MyApp.Secrets` module (the
`AshAuthentication.Secret` behaviour) — never inline literals, and the
redirect URI must match what you registered with the provider, e.g.
`http://localhost:4000/auth/user/google/callback`.

**3. A registration action** — one per provider, handling both sign-up and
sign-in via upsert:

```elixir
create :register_with_google do
  argument :user_info, :map, allow_nil?: false
  argument :oauth_tokens, :map, allow_nil?: false
  upsert? true
  upsert_identity :unique_email

  change AshAuthentication.GenerateTokenChange
  change AshAuthentication.Strategy.OAuth2.IdentityChange

  change fn changeset, _ ->
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    Ash.Changeset.change_attributes(changeset, Map.take(user_info, ["email"]))
  end

  upsert_fields []
  change set_attribute(:confirmed_at, &DateTime.utc_now/0)
end
```

**4. Make `hashed_password` nullable** if you keep the password strategy
alongside OAuth — an OAuth-only user has no password. `attribute
:hashed_password, :string, allow_nil?: true, sensitive?: true`, then
codegen + migrate.

Nothing else changes. `ash_authentication_phoenix` renders the provider
button on `/sign-in` automatically, and `mix kumi.new`'s generated
`AuthOverrides` already styles it to the Kumi card (`Components.OAuth2`),
so it won't arrive grey and off-brand.

### What this means for kumi_admin

Nothing. This is the payoff of kumi_admin having no auth: it never learns
which strategy signed the user in. `KumiAdmin.Actor` reads
`socket.assigns[:current_user]`, populated by the `on_mount` hook you
already pass to `kumi_admin/2`, and a Google-authenticated user and a
password-authenticated user are the same `%User{}` by the time the admin
sees them. Adding a fifth provider requires zero admin changes.

```elixir
kumi_admin "/admin",
  app: MyApp.App,
  on_mount: [{MyAppWeb.LiveUserAuth, :current_user}]
```

## Two-factor authentication

**Be clear-eyed here: `ash_authentication` has no TOTP or 2FA strategy.**
Its add-ons are `confirmation`, `log_out_everywhere` and `audit_log`; its
strategies are the ones listed above. There is nothing to switch on, and
Kumi does not add one — an authentication factor is precisely the kind of
security-critical code that should not be a young project's homegrown
extension.

Two honest paths:

### Delegate MFA to the identity provider (recommended)

If sign-in goes through Google Workspace, Microsoft Entra, Auth0, Okta or
any OIDC provider, MFA is that provider's job and is almost certainly
already enforced by the organisation's own policy. Your app sees an
authenticated identity; enrolment, recovery codes, hardware keys, "trust
this device", and the compliance paperwork all stay upstream.

For an internal or B2B admin this is the whole answer — configure OIDC (or
Google/Auth0 above), turn MFA on in the provider's console, and stop.
Zero security-critical code in your repo.

### Build a TOTP second factor yourself

Only when you must own the whole login: a consumer product with no IdP, or
a regulator that requires an in-app factor. The pieces exist —
[`nimble_totp`](https://hex.pm/packages/nimble_totp) generates and verifies
RFC 6238 codes in a few lines — but the strategy is yours to write against
`AshAuthentication.Strategy.Custom`, and so is everything around it:
encrypted secret storage, single-use recovery codes, replay protection
(reject a code already consumed within its window), enrolment and
re-enrolment flows, rate limiting, and the "half-authenticated" session
state between password success and TOTP success.

If you go this way, treat it as a real feature with its own test suite,
not a strategy block. Nothing in Kumi blocks it; nothing in Kumi helps.

## Where to look in the code

| Question | File |
|---|---|
| How the admin resolves an actor | `kumi_admin/lib/kumi_admin/actor.ex` |
| What happens with no actor | `kumi_admin/lib/kumi_admin/gate.ex` |
| Router options (`on_mount`, `actor`, `sign_in_path`) | `kumi_admin/lib/kumi_admin/router.ex` |
| The sign-in page styling the generator writes | `kumi_new/lib/kumi_new/inject.ex` (`auth_overrides/2`) |
| Which strategies `--auth-strategy` accepts | `kumi_new/lib/kumi_new/args.ex` |

## Honesty note

Unlike `guides/mini-crm.md` and `guides/api.md`, the provider snippets in
this guide were **not** executed end to end — that needs real OAuth client
credentials from Google and GitHub, which this repository does not have.
They are transcribed from `ash_authentication`'s own tutorials against the
`ash_authentication` version this repository is developed against, and the
Kumi-side claims
(the `--auth-strategy` flag, the `Components.OAuth2` override, kumi_admin's
strategy-independence) are verified in code and tests. Verify the OAuth
round trip against your own provider before shipping.
