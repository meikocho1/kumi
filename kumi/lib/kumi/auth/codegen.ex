defmodule Kumi.Auth.Codegen do
  @moduledoc """
  Pure source generation for OAuth2 sign-in strategies.

  `mix kumi.gen.auth` is glue: it resolves module names, calls
  `AshAuthentication`'s public codemods, and prints what it could not do.
  Everything it *writes* comes from here — plain strings, no Igniter, no
  ash_authentication dependency — so the generated source can be unit
  tested in this package without a host application.

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
      instead of emitting DSL that will not compile.
    * `confirmed_at` — only set when the confirmation add-on put that
      attribute there.
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

  defp confirmation_clause(true),
    do: "\n\n  change set_attribute(:confirmed_at, &DateTime.utc_now/0)"

  defp confirmation_clause(_), do: ""

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
