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

    test "without the admin there is nothing to warn about" do
      steps = New.next_steps(%KumiNew.Args{app_name: "my_crm", admin?: false})

      refute steps =~ "/kumi-admin"
      refute steps =~ "full admin"
    end
  end
end
