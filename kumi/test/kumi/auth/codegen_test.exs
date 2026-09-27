defmodule Kumi.Auth.CodegenTest do
  @moduledoc """
  `mix kumi.gen.auth` writes source into somebody's user resource. Source
  that does not parse turns a generator into a wrecking ball, so every
  branch here is asserted to be quotable — that is the check that fails if
  a future edit breaks the string interpolation.

  The OAuth round trip itself cannot be tested here (it needs real client
  credentials from a provider); see `guides/auth.md`, which says so.
  """
  use ExUnit.Case, async: true

  alias Kumi.Auth.Codegen

  @opts [
    secrets: MyApp.Secrets,
    identity_resource: MyApp.Accounts.UserIdentity,
    base_url: "https://login.example.com"
  ]

  defp quotable!(source) do
    assert {:ok, _ast} = Code.string_to_quoted(source),
           "generated source does not parse:\n#{source}"

    source
  end

  # Compiles the one `fn` in `source` whose body mentions `marker`, so a
  # guard is exercised as code rather than only matched as text.
  defp generated_fn!(source, marker) do
    {_ast, fns} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:fn, _, _} = node, acc -> {node, [node | acc]}
        node, acc -> {node, acc}
      end)

    assert [fun] = Enum.filter(fns, &(Macro.to_string(&1) =~ marker))
    {fun, _binding} = Code.eval_quoted(fun)
    fun
  end

  defp user_info_changeset(user_info) do
    Kumi.Test.Account
    |> Ash.Changeset.new()
    |> Ash.Changeset.set_argument(:user_info, user_info)
  end

  describe "strategy/2" do
    test "every supported provider generates parseable DSL naming the secrets module" do
      for provider <- Codegen.providers() do
        source = quotable!(Codegen.strategy(provider, @opts))

        assert source =~ "#{provider} do"
        assert source =~ "client_id MyApp.Secrets"
        assert source =~ "client_secret MyApp.Secrets"
        assert source =~ "identity_resource MyApp.Accounts.UserIdentity"
      end
    end

    test "oidc carries base_url, the named providers do not" do
      # oidc has no endpoints of its own — ash_authentication makes base_url
      # required for it and sets the URLs itself for google/github.
      assert Codegen.strategy(:oidc, @opts) =~ ~s(base_url "https://login.example.com")

      refute Codegen.strategy(:google, @opts) =~ "base_url"
      refute Codegen.strategy(:github, @opts) =~ "base_url"
    end

    test "credentials are never inlined — only the secrets module is named" do
      for provider <- Codegen.providers() do
        source = Codegen.strategy(provider, @opts)
        refute source =~ "System.get_env"
        refute source =~ "Application.get_env"
      end
    end
  end

  describe "register_action/2" do
    test "upserts when the resource has an identity to match a returning user on" do
      source =
        quotable!(
          Codegen.register_action(:google, upsert_identity: :unique_email, confirmed_at?: false)
        )

      assert source =~ "create :register_with_google do"
      assert source =~ "upsert? true"
      assert source =~ "upsert_identity :unique_email"
      # Empty upsert_fields is the point: signing in again must not
      # overwrite the local record from the provider profile.
      assert source =~ "upsert_fields []"
      assert source =~ "change AshAuthentication.GenerateTokenChange"
      assert source =~ "change AshAuthentication.Strategy.OAuth2.IdentityChange"
    end

    test "without an identity it registers only, rather than emitting DSL that cannot compile" do
      source =
        quotable!(Codegen.register_action(:github, upsert_identity: nil, confirmed_at?: false))

      refute source =~ "upsert? true"
      refute source =~ "upsert_identity"
      assert source =~ "registers only"
    end

    test "confirmed_at is set only when the resource actually has that attribute" do
      with_confirmation =
        quotable!(
          Codegen.register_action(:google, upsert_identity: :unique_email, confirmed_at?: true)
        )

      without =
        quotable!(
          Codegen.register_action(:google, upsert_identity: :unique_email, confirmed_at?: false)
        )

      assert with_confirmation =~ "change set_attribute(:confirmed_at, &DateTime.utc_now/0)"
      assert with_confirmation =~ "Unconfirmed user exists already"
      refute without =~ "confirmed_at"
      refute without =~ "Unconfirmed user exists already"
    end

    test "an upsert matched by email only accepts an address the provider verified" do
      # The upsert finds the returning user by email. Without this guard,
      # whoever a provider lets claim an address signs in as its owner.
      for provider <- Codegen.providers() do
        source =
          quotable!(
            Codegen.register_action(provider,
              upsert_identity: :unique_email,
              confirmed_at?: false
            )
          )

        assert source =~ ~s(%{"email_verified" => verified})
      end
    end

    test "without an upsert nothing is matched by email, so there is no guard" do
      for provider <- Codegen.providers() do
        source =
          quotable!(Codegen.register_action(provider, upsert_identity: nil, confirmed_at?: true))

        refute source =~ "email_verified"
      end
    end

    test "the verified-email guard fails closed" do
      guard =
        Codegen.register_action(:oidc, upsert_identity: :unique_email, confirmed_at?: false)
        |> generated_fn!("email_verified")

      verified? = fn user_info -> guard.(user_info_changeset(user_info), %{}).valid? end

      assert verified?.(%{"email" => "a@example.com", "email_verified" => true})
      # Older Assent passes a provider's string claim through uncast.
      assert verified?.(%{"email" => "a@example.com", "email_verified" => "true"})

      refute verified?.(%{"email" => "a@example.com", "email_verified" => false})
      refute verified?.(%{"email" => "a@example.com", "email_verified" => "false"})
      # A provider that does not send the claim at all signs nobody in.
      refute verified?.(%{"email" => "a@example.com"})
    end

    test "the confirmation guard refuses an existing account nobody confirmed" do
      # upsert_fields [] leaves an existing row's confirmed_at alone, so an
      # address registered with a password and never confirmed comes back
      # nil here — and must not be signed in to by the provider's user.
      guard =
        Codegen.register_action(:google, upsert_identity: :unique_email, confirmed_at?: true)
        |> generated_fn!("confirmed_at")

      assert {:error, "Unconfirmed user exists already"} =
               guard.(nil, %{confirmed_at: nil}, %{})

      confirmed = %{confirmed_at: ~U[2026-01-01 00:00:00Z]}
      assert {:ok, ^confirmed} = guard.(nil, confirmed, %{})
    end
  end

  describe "email_verified_notice/2" do
    test "oidc explains why a provider without the claim cannot sign in" do
      notice = Codegen.email_verified_notice(:oidc, :unique_email)

      assert notice =~ "email_verified"
      assert notice =~ "Microsoft Entra ID"
    end

    test "nothing to say when the provider always sends the claim, or nothing is guarded" do
      assert Codegen.email_verified_notice(:google, :unique_email) == nil
      assert Codegen.email_verified_notice(:github, :unique_email) == nil
      assert Codegen.email_verified_notice(:oidc, nil) == nil
    end
  end

  describe "secret_keys/1" do
    test "paths address the strategy inside the authentication DSL" do
      assert [
               {[:authentication, :strategies, :google, :client_id], :google_client_id},
               {[:authentication, :strategies, :google, :client_secret], :google_client_secret},
               {[:authentication, :strategies, :google, :redirect_uri], :google_redirect_uri}
             ] = Codegen.secret_keys(:google)
    end
  end

  describe "callback_path/1" do
    test "matches the route ash_authentication mounts, which is what the provider console needs" do
      assert Codegen.callback_path(:google) == "/auth/user/google/callback"
      assert Codegen.callback_path(:oidc) == "/auth/user/oidc/callback"
    end
  end
end
