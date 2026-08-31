defmodule Kumi.ResolveLocaleTest do
  @moduledoc """
  `mix kumi.plan` / `mix kumi.report` have to answer in the app's language
  without being handed `--app` every time — `app do locale :ja end` is
  documented as the whole switch.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Kumi.Resolve

  test "one declared app decides the locale" do
    assert Resolve.app_locale([Kumi.Test.JaApp]) == :ja
    assert Resolve.app_locale([Kumi.Test.App]) == :en
  end

  test "modules that are not a Kumi.App are ignored" do
    # An `Ash.Resource` answers `spark_is/0` too, so a naive check would
    # find these and then fail reading a locale off them.
    assert Resolve.app_locale([Kumi.Test.Account, Kumi.Test.Domain, Enum]) == :en
    assert Resolve.app_locale([Kumi.Test.Account, Kumi.Test.JaApp]) == :ja
  end

  test "no app, or more than one, stays in the base locale" do
    # Guessing which app speaks for the repository would print a
    # confident wrong language; `--locale` is the way to say it.
    assert Resolve.app_locale([]) == :en
    assert Resolve.app_locale([Kumi.Test.App, Kumi.Test.JaApp]) == :en
  end

  test "an explicit --locale still wins, and an unknown one fails loudly" do
    assert Resolve.locale("ja", nil) == :ja
    assert Resolve.locale("ja", "Kumi.Test.App") == :ja

    assert_raise Mix.Error, ~r/unknown --locale/, fn -> Resolve.locale("fr", nil) end
  end
end
