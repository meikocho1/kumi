defmodule Mix.Tasks.Kumi.NewTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Kumi.New

  describe "next_steps/1" do
    test "says every account the sign-in accepts is a full admin, and how to narrow it" do
      # A fresh app deployed as-is lets anyone register and then edit every
      # resource; the last thing the generator prints is where to say so.
      steps = New.next_steps(%KumiNew.Args{app_name: "my_crm", admin?: true})

      assert steps =~ "Register a user at /register, then visit /kumi-admin."
      assert steps =~ "Every account your sign-in accepts is a full admin there"
      assert steps =~ "`registration_enabled? false`"
      assert steps =~ "`actor: {MyCrmWeb.AdminActor, :fetch}`"
    end

    test "names how to close each strategy that registers users, not only password" do
      # Closing password alone leaves a magic link or a Google sign-in
      # creating accounts, and every one of those is a full admin.
      steps =
        New.next_steps(%KumiNew.Args{
          app_name: "my_crm",
          auth_strategies: ["password", "magic_link"],
          auth_providers: ["google", "github"]
        })

      assert steps =~ "password: set `registration_enabled? false`"
      assert steps =~ "magic_link: set `registration_enabled? false`"
      assert steps =~ "`create :sign_in_with_magic_link`"
      assert steps =~ "google: any Google account can register"
      assert steps =~ "OAuth consent screen"
      assert steps =~ "github: any GitHub account can register"
      assert steps =~ "`actor: {MyCrmWeb.AdminActor, :fetch}`"
    end

    test "an OAuth-only app is not told to close a password strategy it hasn't got" do
      steps =
        New.next_steps(%KumiNew.Args{
          app_name: "my_crm",
          auth_strategies: [],
          auth_providers: ["google"]
        })

      assert steps =~ "google: any Google account can register"
      refute steps =~ "password"
      refute steps =~ "magic_link"
      assert steps =~ "`actor: {MyCrmWeb.AdminActor, :fetch}`"
    end

    test "api_key creates no accounts, so it gets no entry" do
      steps =
        New.next_steps(%KumiNew.Args{
          app_name: "my_crm",
          auth_strategies: ["api_key"],
          auth_providers: []
        })

      refute steps =~ "api_key"
      refute steps =~ "registration_enabled?"
      assert steps =~ "`actor: {MyCrmWeb.AdminActor, :fetch}`"
    end

    test "without the admin there is nothing to warn about" do
      steps = New.next_steps(%KumiNew.Args{app_name: "my_crm", admin?: false})

      refute steps =~ "/kumi-admin"
      refute steps =~ "full admin"
    end
  end
end
