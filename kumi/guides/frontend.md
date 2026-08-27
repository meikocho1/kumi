# Adding a Public Frontend Alongside kumi_admin

Kumi gave you an admin. You also want a public-facing part of the same
Phoenix app — a marketing page, an embeddable widget, anything a visitor with
no login hits directly. This guide answers "how", using the actual working
example in `spikes/chat_ops`: an embeddable chat widget, its `/embed.js`
snippet-injector, and the no-actor Ash policies that let an anonymous visitor
write data safely. Nothing here is hypothetical — every command and header
shown below was actually run against a live server.

Per the blueprint (§9, "API・フロント・examplesの方針"): Kumi does not build a
frontend framework or an API layer of its own — that would be exactly the
kind of thin wrapper the project avoids. Phoenix and LiveView already do this
job; Kumi's job is to document the pattern for coexisting with `kumi_admin`
in the same app, and chat_ops is the worked example, not a new one invented
for this guide.

## What chat_ops has, that you'll recognize

`ChatOps.Core` has three plain-Ash resources (`Site`, `Conversation`,
`Message` — not `Kumi.Resource` shorthand, because policies are
shorthand-unsupported territory), a `ChatOps.App` declaration that puts all
three in `kumi_admin`'s navigation, and a public LiveView (`WidgetLive`) at
`/widget/:public_key` that a visitor reaches with **no session, no login, no
actor at all**. An `/embed.js` controller serves a small script that any
customer can drop on their own site to inject that widget as an `<iframe>`.

That's the whole shape: one Phoenix app, one router, two route trees with
different rules.

## 1. Router coexistence: two route trees, two auth stories

`kumi_admin` is mounted the same way any host app mounts it — inside the
`:browser` pipeline, with an `on_mount` hook that requires the operator to be
logged in:

```elixir
# lib/chat_ops_web/router.ex
scope "/" do
  pipe_through :browser
  import KumiAdmin.Router

  kumi_admin("/kumi-admin",
    app: ChatOps.App,
    on_mount: [{ChatOpsWeb.LiveUserAuth, :current_user}],
    sign_out_path: "/sign-out",
    sign_in_path: "/sign-in",
    user_resource: ChatOps.Accounts.User,
    register_path: "/register"
  )
end
```

The public widget route is deliberately **not** inside
`ash_authentication_live_session` and does **not** pass any `on_mount` auth
hook at all:

```elixir
# Public widget — no auth, no ash_authentication_live_session
# (visitors are never actors; see ChatOps.Core.Site/.Conversation/.Message
# for the no-actor write paths this LiveView uses).
scope "/", ChatOpsWeb do
  pipe_through [:browser, :embeddable]

  live "/widget/:public_key", WidgetLive
end
```

Why they must not share the auth chain: `kumi_admin`'s `on_mount` hook
resolves `socket.assigns.current_user` and is what every policy check in the
admin (`Ash.can?`, the `actor:` passed to reads/writes) is built on. If the
public widget mounted through the same `on_mount`, either (a) it would
redirect a visitor who has no session to a sign-in page — the widget would
never render for the customer's actual visitors — or (b) whoever wrote the
hook would have to special-case "allow no user through" for that one route,
quietly widening the admin's auth guarantee for every other LiveView that
reuses it. Two separate mounts, two separate route trees, is the boring and
correct answer.

**Verified**: `GET /kumi-admin` with no session returns `302` to `/sign-in`,
while `GET /widget/:public_key` with no session at all returns `200` and
renders — proving the two trees really are gated independently, not by
accident:

```
$ curl -s -D - -o /dev/null http://localhost:4011/kumi-admin
HTTP/1.1 302 Found
location: /sign-in

$ curl -s -D - -o /dev/null http://localhost:4011/widget/<public_key>
HTTP/1.1 200 OK
```

## 2. No-actor write policies — the part that will lock you out or open a hole

This is the single most important thing in this guide. `WidgetLive` never
sets `actor:` on anything — there is no actor, ever, on this path. Every Ash
resource in this app defaults to `Ash.Policy.Authorizer` with
`default_access_type :strict` and a blanket `policy always() do
authorize_if actor_present() end`. Left at that, the widget could create
nothing. What actually lets a specific write through is a `bypass` scoped to
one narrow action — not a scoped-down version of the general policy:

```elixir
# lib/chat_ops/core/conversation.ex
actions do
  defaults [:read, :destroy, create: :*, update: :*]

  create :visitor_create do
    description "No-actor create used by the public embed widget."
    accept [:site_id]
  end
end

policies do
  default_access_type :strict

  # No actor exists on the public widget path — this bypass is scoped
  # to exactly one action (accepts only :site_id, defaults status to
  # :new) so a visitor can only ever open a fresh conversation, never
  # touch an existing one or another action.
  bypass action(:visitor_create) do
    authorize_if always()
  end

  policy always() do
    authorize_if actor_present()
  end
end
```

`ChatOps.Core.Message` does the same thing, plus one more guard: its
`visitor_create` action does not even *accept* `:sender` as input — a
`change set_attribute(:sender, :visitor)` pins it server-side, so a visitor
cannot forge a message that renders as if it came from an operator:

```elixir
create :visitor_create do
  description "No-actor create used by the public embed widget."
  accept [:conversation_id, :body]
  change set_attribute(:sender, :visitor)
end
```

The shape to copy: **bypass one specific action, not the resource**. Never
write `bypass action_type(:create) do authorize_if always() end` — that opens
every create action to anyone, forever. A `bypass` scoped to one named action
whose `accept` list is deliberately narrow is the whole safety story.

`ChatOps.Core.Site` needs the mirror image on the read side — the widget has
to look up a site by its public embed key with no actor, but must never be
able to enumerate or browse sites:

```elixir
# lib/chat_ops/core/site.ex
actions do
  defaults [:read, :destroy, create: :*, update: :*]

  read :read_by_public_key do
    get? true
    argument :public_key, :uuid, allow_nil?: false
    filter expr(public_key == ^arg(:public_key))
  end
end

policies do
  default_access_type :strict

  # Narrow bypass: this action can only ever return the single row
  # matching the (secret, hard-to-guess) public_key argument — it can't
  # be used to enumerate sites — so it's safe to open to the actor-less
  # widget page. Everything else on this resource stays operator-only.
  bypass action(:read_by_public_key) do
    authorize_if always()
  end

  policy always() do
    authorize_if actor_present()
  end
end
```

What is *not* open: a plain `Ash.read(ChatOps.Core.Conversation)` with no
actor. Verified directly (no HTTP route exercises this path in chat_ops, so
this was checked against the resource in an `iex`/`mix run` session, not
curl):

```
iex> Ash.read(ChatOps.Core.Conversation)
{:error, %Ash.Error.Forbidden{...}}
```

And the sender-spoofing guard, verified the same way — passing `sender:
:operator` to `visitor_create` is rejected outright, not silently ignored:

```
iex> ChatOps.Core.Message
     |> Ash.Changeset.for_create(:visitor_create, %{
       conversation_id: Ash.UUID.generate(), body: "x", sender: :operator
     })
     |> Ash.create()
{:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.NoSuchInput{input: :sender, ...}]}}
```

And the positive path — an actual anonymous visitor, in a real browser with
no cookie/session pointing at any user, typing into the widget and having
the message actually persist and render back — was driven through a live
page (not a test harness): navigate to `/widget/:public_key`, type "Hello
from an anonymous visitor", press Enter, and the message appears in the
thread. That round-trip is `WidgetLive.handle_event("send_message", ...)` →
`Conversation.visitor_create` (lazily, on first message) →
`Message.visitor_create` → assign back into socket state (see the widget
source below for why there's no read-back query).

## 3. Embedding on a third-party site

`/embed.js` is a controller action, not a LiveView, and it's small on
purpose — it just builds an `<iframe>` pointing back at the widget:

```elixir
# lib/chat_ops_web/controllers/embed_controller.ex
def js(conn, _params) do
  conn
  |> put_resp_content_type("text/javascript", nil)
  |> send_resp(200, script())
end

defp script do
  """
  (function () {
    var currentScript = document.currentScript;
    var siteKey = currentScript && currentScript.getAttribute("data-kumi-site");
    ...
    var iframe = document.createElement("iframe");
    iframe.src = origin + "/widget/" + siteKey;
    ...
    document.body.appendChild(iframe);
  })();
  """
end
```

A customer drops one line on their own site:

```html
<script src="https://your-app.example.com/embed.js" data-kumi-site="THEIR_PUBLIC_KEY"></script>
```

`document.currentScript.src`'s origin is read at runtime, so the same
snippet works from any deploy without hardcoding a host, and no CORS headers
are set on the response — an `<iframe src>` load is a plain cross-origin
*navigation*, not a fetch/XHR, so CORS (which only governs script-initiated
requests) has nothing to do with it. Don't cargo-cult
`Access-Control-Allow-Origin` onto this response; nothing reads it.

## 4. The exemptions that cost a real 403 — found by curl, not by tests

Two ordinary Phoenix defaults exist specifically to stop cross-site requests
that look exactly like what this feature *is*. Both were only caught by
firing a real HTTP request at the running server — a green `mix test` run
does not exercise either failure mode.

### 4a. CSRF blocks the embed snippet itself

`protect_from_forgery` (part of the standard `:browser` pipeline) 403s a
cross-origin `GET` of a `js`-format route — which is exactly what a
`<script src=".../embed.js">` tag on a customer's site produces. chat_ops
solves this with a second, narrower pipeline that never adds CSRF protection
in the first place:

```elixir
# The embed snippet is BY DESIGN a cross-origin <script src> include from
# customer sites — it must bypass protect_from_forgery, which 403s
# cross-origin GETs of js-format routes (Plug.CSRFProtection). It carries
# no session data, so the plain :browser protections don't apply to it.
pipeline :embed_js do
  plug :accepts, ["js"]
end

scope "/", ChatOpsWeb do
  pipe_through :embed_js

  get "/embed.js", EmbedController, :js
end
```

**Honest limitation**: the 403 this guards against is *not* reproducible in
`ExUnit`. `Phoenix.ConnTest` sets `:plug_skip_csrf_protection` on every test
connection, so a controller test through `:browser` would pass whether or
not `/embed.js` used the `:embed_js` pipeline — the test would be green
either way, telling you nothing. `test/chat_ops_web/controllers/
embed_controller_test.exs` says this in its own comment rather than
pretending to cover it. This run verified `/embed.js` returns `200` through
the exempt `:embed_js` pipeline (see the table below); it did **not**
reproduce the 403 itself (that would require routing the same request
through the plain `:browser` pipeline instead, which the running app
never does) — take the 403 claim as inherited from the router's own comment
and from F111 in the friction log, not as re-verified in this session.

### 4b. Framing controls block the customer-site iframe — and the header you'll reach for is the wrong one

`put_secure_browser_headers` (also part of `:browser`) blocks the exact thing
`/embed.js` just built: a customer site framing `/widget/:public_key` in an
`<iframe>`. Every tutorial and every StackOverflow answer will tell you the
culprit is `X-Frame-Options: SAMEORIGIN`. On **Phoenix 1.8 that header is not
sent at all.** Verified against a running 1.8.13 app — the full header set on
a plain `:browser` route:

```
$ curl -s -D - -o /dev/null http://localhost:4011/
HTTP/1.1 200 OK
x-permitted-cross-domain-policies: none
x-content-type-options: nosniff
content-security-policy: base-uri 'self'; frame-ancestors 'self';
referrer-policy: strict-origin-when-cross-origin
```

No `x-frame-options`. The framing control is the CSP `frame-ancestors 'self'`
directive, which supersedes `X-Frame-Options` in every browser that
implements both. So the fix is to override the CSP for the one embeddable
route — and to override it rather than delete it, because the same header
carries `base-uri 'self'`, which has nothing to do with framing and should
survive:

```elixir
# The widget is loaded inside an <iframe> ON CUSTOMER SITES, and
# put_secure_browser_headers blocks that TWICE over: once with
# `x-frame-options: SAMEORIGIN`, and once with the `frame-ancestors 'self'`
# directive of its `content-security-policy`. Browsers honour the CSP
# directive and ignore x-frame-options when both are present, so dropping
# only the latter leaves cross-site framing broken — a header-only test
# stays green while a real customer site still sees an empty frame.
# The CSP is re-emitted without frame-ancestors rather than deleted, so its
# `base-uri` protection survives.
pipeline :embeddable do
  plug :allow_cross_site_framing
end

defp allow_cross_site_framing(conn, _opts) do
  conn
  |> Plug.Conn.delete_resp_header("x-frame-options")
  |> Plug.Conn.put_resp_header("content-security-policy", "base-uri 'self';")
end

scope "/", ChatOpsWeb do
  pipe_through [:browser, :embeddable]

  live "/widget/:public_key", WidgetLive
end
```

The `delete_resp_header("x-frame-options")` line stays even though Phoenix
1.8 never sets it: a CDN, a reverse proxy, or a host on an older Phoenix
will, and this pipeline is the one place that decides this route is
framable.

**How this was found, and why it matters more than the code.** chat_ops
shipped this pipeline deleting `x-frame-options` and nothing else, with a
test asserting exactly that:

```elixir
# The version that was green while the feature was broken:
assert get_resp_header(conn, "x-frame-options") == []
```

That assertion passes **vacuously** — it asserts the absence of a header
nothing in the stack ever set. It would pass with the `:embeddable` pipeline
deleted entirely. Meanwhile a real cross-origin `<iframe>`, loaded in an
actual browser from a second origin, failed:

```
[ERROR] Framing 'http://localhost:4011/...' violates the following Content
Security Policy directive: "frame-ancestors 'self'". The request has been
blocked.
```

`ExUnit` does not fake away response headers the way it fakes away CSRF, so
this one *was* testable all along — it just wasn't tested for the right
header. The corrected test asserts the thing that actually controls framing:

```elixir
test "widget page drops BOTH framing controls so customer sites can iframe it", %{conn: conn} do
  conn = get(conn, "/widget/#{site.public_key}")
  assert response(conn, 200)
  assert get_resp_header(conn, "x-frame-options") == []

  assert [csp] = get_resp_header(conn, "content-security-policy")
  refute csp =~ "frame-ancestors"
  assert csp =~ "base-uri 'self'"
end
```

The `refute` is the load-bearing line, and the `assert csp =~ "base-uri"`
is there so a future "just delete the header" simplification fails the test.

## Verification actually run against a live server

`chat_ops` was started with `PORT=4011 mix phx.server` (its
`config/runtime.exs` already reads `PORT` for all environments — no file was
edited to pick the port) against its own dev database
(`chat_ops_dev`, docker `kumi_db` on `localhost:5434`; the database already
existed, `mix ash.setup` reported "already up").

| Check | Result |
|---|---|
| `GET /embed.js` | `200`, `content-type: text/javascript`, body is the real injector script (`data-kumi-site`, `/widget/`, `iframe` all present) |
| `GET /embed.js` headers | no `x-frame-options` present (never was; this route isn't framed) |
| `GET /widget/:public_key` | `200`, no `x-frame-options`, `content-security-policy: base-uri 'self';` |
| `GET /` (plain `:browser`, control) | `200`, `content-security-policy: base-uri 'self'; frame-ancestors 'self';` — proving the exemption is scoped to the one route |
| `GET /widget/:public_key` in a real cross-origin `<iframe>`, **before** the §4b fix | **blocked** by `content-security-policy: frame-ancestors 'self'` (console error captured) |
| `GET /widget/:public_key` in a real cross-origin `<iframe>`, **after** the §4b fix | loads; widget content visible, zero console errors |
| `GET /kumi-admin` (no session) | `302` to `/sign-in` |
| Anonymous visitor typing a message in a real browser | message persists and renders (`Conversation.visitor_create` + `Message.visitor_create`) |
| `Ash.read(ChatOps.Core.Conversation)`, no actor | `{:error, %Ash.Error.Forbidden{}}` |
| `Message.visitor_create` with `sender: :operator` forced in | `{:error, %Ash.Error.Invalid{... NoSuchInput input: :sender}}` |

## Where you still write glue code today

- **You have to know which framing header your Phoenix version actually
  sends.** Nothing in Kumi or kumi_admin papers over §4b: making a route
  embeddable means hand-writing a pipeline that overrides CSP
  `frame-ancestors` (and, defensively, deletes `x-frame-options`), and
  knowing that the header everyone names is not the one 1.8 sends. A
  first-class `embeddable` option on the Kumi side would be a reasonable
  future module; today it is host code.
- **`frame-ancestors` is dropped, not narrowed.** The pipeline above makes the
  widget framable by *any* origin, because chat_ops has no per-site allowed
  origins yet. A real product would emit
  `frame-ancestors https://customer.example` from the `Site` record's
  registered domain. That is a data-model change (an `allowed_origins` field
  plus a plug that reads it), not a header change.
- **No public read policy at all** — `WidgetLive` never queries the DB for
  the messages it renders; it only ever shows what it created in the same
  socket session. That's a real, called-out cut corner (a page refresh loses
  history), not an oversight — writing a real "read your own conversation"
  policy (scoped by a session token, not just `public_key`) is separate,
  harder work this guide does not attempt.
- **No CSRF coverage for the embed route in `ExUnit`, ever.**
  `Phoenix.ConnTest` disables CSRF checking unconditionally; there is no
  supported way to assert "this route would 403 a cross-origin browser GET"
  from inside the test suite. A real HTTP check against a running server (as
  done in this guide) is the only verification that exists for this class of
  bug.
- **This is a router/policy pattern, not a Kumi feature.** Kumi does not
  generate the `:embed_js` / `:embeddable` pipelines, the `bypass` policies,
  or the widget LiveView for you — `mix kumi.install` and `mix
  kumi_admin.install` only ever wire up the admin half. Everything in this
  guide is you, writing plain Phoenix and plain Ash, the same escape hatch
  D1 always promises; Kumi's contribution is that `ChatOps.App`'s
  `resources`/`navigation` block still drives the admin side of the same
  three resources with zero extra code.
- **No rate limiting on the no-actor create paths.** `Conversation
  .visitor_create` and `Message.visitor_create` are open to anyone who can
  reach the widget URL — nothing in this guide's slice throttles a visitor
  hammering `send_message`. That's an intentional deferral for this walk
  through, not a general Kumi position on the topic.
