defmodule Kumi.AppTest do
  use ExUnit.Case, async: true

  alias Kumi.App.Info

  test "Info reads back exactly what was declared" do
    assert Info.name(Kumi.Test.App) == :test_app
    assert Info.title(Kumi.Test.App) == "Test App"
    assert Info.resources(Kumi.Test.App) == [Kumi.Test.Account]
    assert Info.navigation(Kumi.Test.App) == [Kumi.Test.Account]

    assert [%Kumi.App.Dsl.Workflow{name: :onboarding, stages: [:invited, :active]}] =
             Info.workflows(Kumi.Test.App)

    assert [%Kumi.App.Dsl.Dashboard{name: :overview, metrics: [metric]}] =
             Info.dashboards(Kumi.Test.App)

    assert metric.name == :account_count
  end
end
