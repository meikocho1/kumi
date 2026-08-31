defmodule Kumi.AppTest do
  use ExUnit.Case, async: true

  alias Kumi.App.Info

  test "Info reads back exactly what was declared" do
    assert Info.name(Kumi.Test.App) == :test_app
    assert Info.title(Kumi.Test.App) == "Test App"
    assert Info.resources(Kumi.Test.App) == [Kumi.Test.Account]
    assert Info.navigation(Kumi.Test.App) == [Kumi.Test.Account]
    assert Info.related_limit(Kumi.Test.App) == 10

    assert [
             %Kumi.App.Dsl.Workflow{
               name: :onboarding,
               resource: Kumi.Test.Account,
               field: :industry,
               stages: [:invited, :active]
             }
           ] = Info.workflows(Kumi.Test.App)

    assert [%Kumi.App.Dsl.Dashboard{name: :overview, metrics: [metric]}] =
             Info.dashboards(Kumi.Test.App)

    assert metric.name == :account_count
    assert metric.resource == Kumi.Test.Account
    assert metric.kind == :count
  end

  defmodule AppWithExplicitRelatedLimit do
    use Kumi.App

    app do
      name(:limit_app)
    end

    resources do
      resource(Kumi.Test.Account)
    end

    admin do
      navigation([Kumi.Test.Account])
      related_limit(3)
    end
  end

  test "related_limit reads back an explicit value" do
    assert Info.related_limit(AppWithExplicitRelatedLimit) == 3
  end

  describe "locale and labels" do
    test "an app that declares neither is English with no labels" do
      assert Info.locale(Kumi.Test.App) == :en
      assert Info.labels(Kumi.Test.App) == %{}
      assert Info.label(Kumi.Test.App, Kumi.Test.Account) == nil
    end

    test "Info reads back the declared locale and every kind of label" do
      app = Kumi.Test.JaApp

      assert Info.locale(app) == :ja
      assert Info.title(app) == "ためしアプリ"

      assert Info.label(app, Kumi.Test.Account) == "取引先"
      assert Info.label(app, Kumi.Test.Account, :industry) == "業種"
      assert Info.label(app, :onboarding) == "オンボーディング"
      assert Info.label(app, :onboarding, :invited) == "招待済み"
      assert Info.label(app, :overview) == "概要"
      assert Info.label(app, :overview, :account_count) == "取引先数"
    end

    # `nil` is the whole contract for "no label declared" — the caller owns
    # the fallback, so this must not become an empty string or the humanized
    # name.
    test "an undeclared label is nil, not a derived string" do
      assert Info.label(Kumi.Test.JaApp, Kumi.Test.Account, :inserted_at) == nil
      assert Info.label(Kumi.Test.JaApp, :nope) == nil
    end
  end
end
