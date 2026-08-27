# Security policy

## Supported versions

Kumi is pre-1.0. Only the latest tagged release receives fixes; there are
no maintained backport branches yet. When 1.0 lands this section will say
which minor versions are supported and for how long.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting on this repository:
**Security → Report a vulnerability**. That opens a private thread
visible only to the maintainers, and it works without you needing an
email address for anyone.

Please include:

- what an attacker can do, and what access they need to start;
- the smallest reproduction you have (a resource definition and a
  command is usually enough);
- the affected package (`kumi`, `kumi_admin`, `kumi_new`,
  `kumi_storage`) and version.

You should get an acknowledgement within a week. Kumi is maintained by a
very small number of people, so please allow time for a fix before any
public disclosure, and tell us if you have a disclosure deadline.

## Areas worth extra scrutiny

If you're looking for where the interesting surface is:

- **`mix kumi.apply`** executes DDL against a live database. It is
  restricted to changes classified SAFE, gated by an explicit allowlist,
  runs in a single transaction, and re-introspects afterwards to verify
  the result. It also refuses to run outside `MIX_ENV=dev`. Any path that
  gets a destructive statement past those gates is a vulnerability, not a
  bug report.
- **`Kumi.Plan.Safety`** must fail closed: an unrecognised type change is
  classified DANGEROUS rather than assumed harmless. A case where it
  fails *open* is a security issue.
- **`kumi_storage`**'s upload path validates content type and size and
  rejects path traversal in filenames; its `Plug` serves files by
  generated key only. Traversal, unrestricted type acceptance, or reading
  outside the configured root are in scope.
- **`kumi_admin`** deliberately has no authentication of its own — it
  consumes the host application's `on_mount` hooks and actor. Reads that
  bypass the host's Ash policies, or a rendered value escaping HTML
  encoding, are in scope. "The admin is reachable without logging in" is
  a host configuration issue unless the router macro itself is at fault.

## Out of scope

- Findings that require an already-compromised developer machine, or
  running `mix kumi.apply` in production against the explicit
  `MIX_ENV=dev` guard.
- Vulnerabilities in Ash, AshPostgres, Phoenix, or Postgres themselves —
  please report those upstream. We're glad to hear about them anyway if
  Kumi's usage makes them materially worse.
