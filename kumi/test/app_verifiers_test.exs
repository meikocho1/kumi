defmodule Kumi.AppVerifiersTest do
  use ExUnit.Case, async: true

  import Spark.Test

  test "happy path compiles with no DSL errors" do
    refute_dsl_errors do
      defmodule Elixir.Kumi.AppVerifiersTest.Happy do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        workflow(:w, resource: Kumi.Test.Account, field: :industry, stages: [:a])

        dashboard :d do
          metric(:m, resource: Kumi.Test.Account)
        end
      end
    end
  end

  test "rejects a resource that isn't an Ash.Resource" do
    assert_dsl_error(%Spark.Error.DslError{path: [:resources, :resource]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.NotAResource do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          # String is a real, loaded module — just not an Ash.Resource.
          resource String
        end
      end
    end
  end

  test "rejects an app with no `app do ... end` block (name unset)" do
    assert_dsl_error(%Spark.Error.DslError{path: [:app, :name]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.NoAppBlock do
        use Kumi.App

        resources do
          resource Kumi.Test.Account
        end
      end
    end
  end

  test "rejects a resource whose primary key isn't exactly [:id]" do
    defmodule Elixir.Kumi.AppVerifiersTest.CustomPrimaryKeyResource do
      @moduledoc false
      use Ash.Resource, data_layer: :embedded

      attributes do
        attribute :key, :string do
          primary_key? true
          allow_nil? false
          public? true
        end
      end
    end

    assert_dsl_error(%Spark.Error.DslError{path: [:resources, :resource]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.CustomPrimaryKeyApp do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.AppVerifiersTest.CustomPrimaryKeyResource
        end
      end
    end
  end

  test "rejects duplicate navigation entries" do
    assert_dsl_error(%Spark.Error.DslError{path: [:admin, :navigation]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.DuplicateNavigation do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        admin do
          navigation([Kumi.Test.Account, Kumi.Test.Account])
        end
      end
    end
  end

  test "rejects duplicate metric names within one dashboard" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.DuplicateMetricName do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          metric(:n, resource: Kumi.Test.Account)
          metric(:n, resource: Kumi.Test.Account)
        end
      end
    end
  end

  test "rejects a navigation entry not declared in resources" do
    assert_dsl_error(%Spark.Error.DslError{path: [:admin, :navigation]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.BadNavigation do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        admin do
          navigation([Kumi.Test.Deal])
        end
      end
    end
  end

  test "rejects a workflow with no stages" do
    assert_dsl_error(%Spark.Error.DslError{path: [:workflows, :workflow, :empty]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.EmptyWorkflow do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        workflow(:empty, resource: Kumi.Test.Account, field: :industry)
      end
    end
  end

  test "rejects a dashboard with no metrics" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :empty]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.EmptyDashboard do
        use Kumi.App

        app do
          name :ok
        end

        dashboard :empty do
        end
      end
    end
  end

  test "rejects duplicate resource entries" do
    assert_dsl_error(%Spark.Error.DslError{path: [:resources]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.DuplicateResource do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
          resource Kumi.Test.Account
        end
      end
    end
  end

  test "rejects duplicate workflow names" do
    assert_dsl_error(%Spark.Error.DslError{path: [:workflows]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.DuplicateWorkflow do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        workflow(:dup, resource: Kumi.Test.Account, field: :industry, stages: [:a])
        workflow(:dup, resource: Kumi.Test.Account, field: :industry, stages: [:b])
      end
    end
  end

  test "rejects duplicate dashboard names" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.DuplicateDashboard do
        use Kumi.App

        app do
          name :ok
        end

        dashboard :dup do
          metric(:m1, resource: Kumi.Test.Account)
        end

        dashboard :dup do
          metric(:m2, resource: Kumi.Test.Account)
        end
      end
    end
  end

  test "rejects a metric whose resource is not declared in resources" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.UndeclaredMetricResource do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          metric(:m, resource: Kumi.Test.Deal)
        end
      end
    end
  end

  test "rejects a :sum metric with no field" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.SumWithoutField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          metric(:m, resource: Kumi.Test.Account, kind: :sum)
        end
      end
    end
  end

  test "rejects a :sum metric whose field does not exist on the resource" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.SumWithBadField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          metric(:m, resource: Kumi.Test.Account, kind: :sum, field: :nonexistent)
        end
      end
    end
  end

  test "accepts a :sum metric over a decimal field" do
    refute_dsl_errors do
      defmodule Elixir.Kumi.AppVerifiersTest.SumOnDecimalField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Deal
        end

        dashboard :d do
          metric(:pipeline_value, resource: Kumi.Test.Deal, kind: :sum, field: :amount)
        end
      end
    end
  end

  test "rejects a :sum metric whose field is not a numeric type" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.SumOnNonNumericField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          # :name is a :string attribute — Ash.sum/3 would compile here and
          # only fail at request time, inside the admin dashboard.
          metric(:m, resource: Kumi.Test.Account, kind: :sum, field: :name)
        end
      end
    end
  end

  test "rejects a :count metric that sets field" do
    assert_dsl_error(%Spark.Error.DslError{path: [:dashboards, :dashboard, :d]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.CountWithField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        dashboard :d do
          metric(:m, resource: Kumi.Test.Account, kind: :count, field: :name)
        end
      end
    end
  end

  test "rejects a workflow whose resource is not declared in resources" do
    assert_dsl_error(%Spark.Error.DslError{path: [:workflows, :workflow, :w]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.UndeclaredWorkflowResource do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        workflow(:w, resource: Kumi.Test.Deal, field: :stage, stages: [:lead])
      end
    end
  end

  test "rejects a workflow whose field does not exist on the resource" do
    assert_dsl_error(%Spark.Error.DslError{path: [:workflows, :workflow, :w]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.NonexistentWorkflowField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Account
        end

        workflow(:w, resource: Kumi.Test.Account, field: :nonexistent, stages: [:a])
      end
    end
  end

  test "rejects a workflow whose field is private" do
    defmodule Elixir.Kumi.AppVerifiersTest.PrivateFieldResource do
      @moduledoc false
      use Ash.Resource, data_layer: :embedded

      attributes do
        attribute :secret, :string do
          public? false
        end
      end
    end

    assert_dsl_error(%Spark.Error.DslError{path: [:workflows, :workflow, :w]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.PrivateWorkflowField do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.AppVerifiersTest.PrivateFieldResource
        end

        workflow(:w,
          resource: Kumi.AppVerifiersTest.PrivateFieldResource,
          field: :secret,
          stages: [:a]
        )
      end
    end
  end

  test "rejects stages not a subset of the field's one_of constraint" do
    assert_dsl_error(%Spark.Error.DslError{path: [:workflows, :workflow, :w]}) do
      defmodule Elixir.Kumi.AppVerifiersTest.StagesNotInOneOf do
        use Kumi.App

        app do
          name :ok
        end

        resources do
          resource Kumi.Test.Deal
        end

        workflow(:w, resource: Kumi.Test.Deal, field: :stage, stages: [:lead, :bogus])
      end
    end
  end

  describe "locale" do
    test "an unknown locale is rejected rather than silently falling back to English" do
      assert_dsl_error(%Spark.Error.DslError{path: [:app, :locale]}) do
        defmodule Elixir.Kumi.AppVerifiersTest.BadLocale do
          use Kumi.App

          app do
            name :ok
            locale(:jp)
          end

          resources do
            resource Kumi.Test.Account
          end
        end
      end
    end

    test "a supported locale compiles" do
      refute_dsl_errors do
        defmodule Elixir.Kumi.AppVerifiersTest.JaLocale do
          use Kumi.App

          app do
            name :ok
            locale(:ja)
          end

          resources do
            resource Kumi.Test.Account
          end
        end
      end
    end
  end

  describe "labels" do
    test "labels for declared resources, workflows, dashboards and their parts compile" do
      refute_dsl_errors do
        defmodule Elixir.Kumi.AppVerifiersTest.GoodLabels do
          use Kumi.App

          app do
            name :ok
            locale(:ja)
          end

          resources do
            resource Kumi.Test.Account
          end

          admin do
            navigation([Kumi.Test.Account])

            labels(%{
              Kumi.Test.Account => "取引先",
              {Kumi.Test.Account, :industry} => "業種",
              :onboarding => "オンボーディング",
              {:onboarding, :invited} => "招待済み",
              :overview => "概要",
              {:overview, :account_count} => "取引先数"
            })
          end

          workflow(:onboarding,
            resource: Kumi.Test.Account,
            field: :industry,
            stages: [:invited, :active]
          )

          dashboard :overview do
            metric(:account_count, resource: Kumi.Test.Account)
          end
        end
      end
    end

    test "a label for a resource the app never declared is rejected" do
      assert_dsl_error(%Spark.Error.DslError{path: [:admin, :labels]}) do
        defmodule Elixir.Kumi.AppVerifiersTest.LabelUnknownResource do
          use Kumi.App

          app do
            name :ok
          end

          resources do
            resource Kumi.Test.Account
          end

          admin do
            labels(%{Kumi.Test.Deal => "商談"})
          end
        end
      end
    end

    test "a label for an attribute the resource does not have is rejected" do
      assert_dsl_error(%Spark.Error.DslError{path: [:admin, :labels]}) do
        defmodule Elixir.Kumi.AppVerifiersTest.LabelUnknownField do
          use Kumi.App

          app do
            name :ok
          end

          resources do
            resource Kumi.Test.Account
          end

          admin do
            labels(%{{Kumi.Test.Account, :industy} => "業種"})
          end
        end
      end
    end

    test "a label for a stage the workflow does not declare is rejected" do
      assert_dsl_error(%Spark.Error.DslError{path: [:admin, :labels]}) do
        defmodule Elixir.Kumi.AppVerifiersTest.LabelUnknownStage do
          use Kumi.App

          app do
            name :ok
          end

          resources do
            resource Kumi.Test.Account
          end

          admin do
            labels(%{{:onboarding, :archived} => "アーカイブ"})
          end

          workflow(:onboarding,
            resource: Kumi.Test.Account,
            field: :industry,
            stages: [:invited]
          )
        end
      end
    end

    test "a non-string label is rejected" do
      assert_dsl_error(%Spark.Error.DslError{path: [:admin, :labels]}) do
        defmodule Elixir.Kumi.AppVerifiersTest.LabelNotAString do
          use Kumi.App

          app do
            name :ok
          end

          resources do
            resource Kumi.Test.Account
          end

          admin do
            labels(%{Kumi.Test.Account => :account})
          end
        end
      end
    end
  end
end
