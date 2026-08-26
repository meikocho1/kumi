defmodule KumiAdmin.LabelTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Label

  test "plural/1 adds a plain s by default" do
    assert Label.plural(MyApp.Crm.Deal) == "Deals"
    assert Label.plural(MyApp.Crm.Account) == "Accounts"
  end

  test "plural/1 turns a trailing consonant-y into -ies" do
    assert Label.plural(MyApp.Crm.Company) == "Companies"
  end

  test "plural/1 does not turn a trailing vowel-y into -ies" do
    assert Label.plural(MyApp.Crm.Journey) == "Journeys"
  end

  test "plural/1 adds -es after s/x/z/ch/sh" do
    assert Label.plural(MyApp.Crm.Address) == "Addresses"
    assert Label.plural(MyApp.Crm.Branch) == "Branches"
  end
end
