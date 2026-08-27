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
end
