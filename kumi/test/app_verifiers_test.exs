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
end
