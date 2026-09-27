defmodule Kumi.Auth.Codegen do
  @moduledoc """
  Pure source generation for OAuth2 sign-in strategies.

  `mix kumi.gen.auth` is glue: it resolves module names, calls
  `AshAuthentication`'s public codemods, and prints what it could not do.
  Everything it *writes* comes from here — plain strings, no Igniter, no
  ash_authentication dependency — so the generated source can be unit
  tested in this package without a host application. So does the one
  notice whose wording depends on what was generated.

  This is the same split as `Kumi.Resource.Codegen`: one function is the
  single source of truth for what gets emitted, and the test asserts the
  emitted source parses.
  """

  @providers ~w(google github oidc)a

  @doc "The providers this module can generate."
  @spec providers() :: [atom()]
  def providers, do: @providers

  @doc """
  The `authentication > strategies` block for `provider`.

  `:oidc` carries a `base_url` because, unlike the named providers, it has
  no endpoints of its own — every other provider's URLs are set by
  ash_authentication.
  """
  @spec strategy(atom(), keyword()) :: String.t()
  def strategy(:oidc, opts) do
    """
    oidc do
      client_id #{inspect(opts[:secrets])}
      redirect_uri #{inspect(opts[:secrets])}
      client_secret #{inspect(opts[:secrets])}
      base_url #{inspect(opts[:base_url])}
      identity_resource #{inspect(opts[:identity_resource])}
    end
    """
  end

  def strategy(provider, opts) when provider in @providers do
    """
    #{provider} do
      client_id #{inspect(opts[:secrets])}
      redirect_uri #{inspect(opts[:secrets])}
      client_secret #{inspect(opts[:secrets])}
      identity_resource #{inspect(opts[:identity_resource])}
    end
    """
  end

  @doc """
  The `register_with_<provider>` action.

  Handles registration and sign-in in one action, which is how every
  ash_authentication OAuth2 flow is wired: the provider hands back a
  profile, and whether that profile is new is not the caller's problem.

  Two things vary, and both are detected from the resource rather than
  assumed:

    * `upsert_identity` — without a unique identity there is nothing to
      match a returning user on, so the action registers only and says so
      instead of emitting DSL that will not compile. With one, a returning
      user is matched by email, so the action also rejects any address
      the provider has not marked `email_verified`. It fails closed: a
      provider that does not send the claim cannot sign anyone in.
    * `confirmed_at` — only set when the confirmation add-on put that
      attribute there, together with ash_authentication's own guard
      against signing in to an existing account nobody confirmed.
  """
  @spec register_action(atom(), keyword()) :: String.t()
  def register_action(provider, opts) do
    """
    create :register_with_#{provider} do
      description "Registers or signs in a user via #{provider}."
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
    #{upsert_clause(opts[:upsert_identity])}
      change AshAuthentication.GenerateTokenChange
      # Persists the provider's iss/sub claims against the identity resource.
      change AshAuthentication.Strategy.OAuth2.IdentityChange
    #{email_verified_clause(opts[:upsert_identity])}
      change fn changeset, _ctx ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)
        Ash.Changeset.change_attributes(changeset, Map.take(user_info, ["email"]))
      end#{confirmation_clause(opts[:confirmed_at?])}
    end
    """
  end

  defp upsert_clause(nil) do
    """

      # No unique identity was found on this resource, so this action
      # registers only — a returning user would fail the uniqueness check.
      # Add a unique identity to the resource, then turn this into an
      # upsert. See guides/auth.md.
    """
  end

  defp upsert_clause(identity) do
    """

      upsert? true
      upsert_identity #{inspect(identity)}
      # Empty on purpose: a returning user must not have their record
      # overwritten from the provider profile on every sign-in.
      upsert_fields []
    """
  end

  # Without an upsert nothing is matched by email, so there is nothing for
  # an unverified address to take over.
  defp email_verified_clause(nil), do: ""

  # Every provider gets this, not only oidc: Assent, which
  # ash_authentication's OAuth2 strategies are built on, sets
  # `email_verified` for google and github as well. Older Assent passes a
  # provider's string "true" through uncast, hence both.
  defp email_verified_clause(_identity) do
    """

      # The upsert above matches a returning user by email, so only an
      # address the provider has verified may sign in to an existing account.
      change fn changeset, _ctx ->
        case Ash.Changeset.get_argument(changeset, :user_info) do
          %{"email_verified" => verified} when verified in [true, "true"] ->
            changeset

          _ ->
            Ash.Changeset.add_error(changeset,
              field: :user_info,
              message: "the provider did not verify this email address"
            )
        end
      end
    """
  end

  # The after_action is ash_authentication's own, from its 4.x OAuth2
  # tutorials: it stops the pre-hijack where someone registers an address
  # with a password, never confirms it, and waits for the owner to sign in
  # with a provider.
  defp confirmation_clause(true) do
    """


      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      # An existing user keeps their own confirmed_at. nil means nobody ever
      # proved they own this address: refuse rather than sign in to it.
      change after_action(fn _changeset, user, _ctx ->
        case user.confirmed_at do
          nil -> {:error, "Unconfirmed user exists already"}
          _ -> {:ok, user}
        end
      end)
    """
    |> String.trim_trailing()
  end

  defp confirmation_clause(_), do: ""

  @doc """
  What `mix kumi.gen.auth` has to tell the user about the verified-email
  check in `register_action/2`, or `nil` when there is nothing to say.

  Google and GitHub always report whether the address is verified. A
  generic OpenID Connect provider may not send `email_verified` at all,
  and then the check rejects every sign-in — which is the safe failure,
  but only if the user knows why it happens.
  """
  @spec email_verified_notice(atom(), atom() | nil) :: String.t() | nil
  def email_verified_notice(:oidc, identity) when not is_nil(identity) do
    """
    oidc: register_with_oidc matches a returning user by email, so it only
    accepts a sign-in when the provider's user info says
    `email_verified: true`.

    Check that your provider sends that claim. Most do; some do not by
    default — Microsoft Entra ID is the usual one — and against those
    every sign-in fails with "the provider did not verify this email
    address" until it does. Do not delete the check to make sign-in
    work: without it, anyone the provider lets claim an address signs in
    as the user who owns it here.
    """
  end

  def email_verified_notice(_provider, _identity), do: nil

  @doc """
  The application-env keys `Secrets` will read for `provider`, in the
  order `mix kumi.gen.auth` generates `secret_for/4` clauses for them.
  """
  @spec secret_keys(atom()) :: [{[atom()], atom()}]
  def secret_keys(provider) do
    for key <- [:client_id, :client_secret, :redirect_uri] do
      {[:authentication, :strategies, provider, key], :"#{provider}_#{key}"}
    end
  end

  @doc "The callback path a provider console has to be told about."
  @spec callback_path(atom()) :: String.t()
  def callback_path(provider), do: "/auth/user/#{provider}/callback"
end
