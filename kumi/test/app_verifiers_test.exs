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

        workflow :w do
          stages([:a])
        end

        dashboard :d do
          metric(:m)
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

        workflow :empty do
        end
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

        workflow :dup do
          stages([:a])
        end

        workflow :dup do
          stages([:b])
        end
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
          metric(:m1)
        end

        dashboard :dup do
          metric(:m2)
        end
      end
    end
  end
end
