defmodule KumiAdmin.SlugTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Slug

  test "for_resource/1 is the last module segment, underscored" do
    assert Slug.for_resource(KumiAdmin.Test.Account) == "account"
    assert Slug.for_resource(MyApp.Crm.DealNote) == "deal_note"
  end

  test "resolve/2 finds the app resource whose slug matches" do
    assert Slug.resolve(KumiAdmin.Test.App, "account") == KumiAdmin.Test.Account
    assert Slug.resolve(KumiAdmin.Test.App, "contact") == KumiAdmin.Test.Contact
  end

  test "resolve/2 returns nil for an unknown slug" do
    assert Slug.resolve(KumiAdmin.Test.App, "nope") == nil
  end
end
