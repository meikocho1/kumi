defmodule KumiAdmin.MetricValueTest do
  @moduledoc """
  `KumiAdmin.MetricValue.fetch/2` has no injectable seam — it calls
  `Ash.count/2`/`Ash.sum/3` directly on the `Metric`'s resource — so the
  forbidden/error branches are exercised against real Ash resources
  (in-memory `Ash.DataLayer.Ets`) with real `Ash.Policy.Authorizer`
  policies rather than an injected result. `Kumi.App.Dsl.Metric` is a
  plain struct, so it's constructed directly without going through the
  `Kumi.App` DSL macro.
  """

  use ExUnit.Case, async: true

  alias Kumi.App.Dsl.Metric
  alias KumiAdmin.MetricValue
  alias KumiAdmin.Test.Widget

  # A check that fails without raising, used for the plain `:forbidden`
  # branch (`Ash.can?`/`Ash.count` return `{:error, %Ash.Error.Forbidden{}}`).
  defmodule DenyCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck
    def describe(_opts), do: "always denies"
    def match?(_actor, _context, _opts), do: false
  end

  # A check that errors (without a bare `raise`) so the underlying Ash call
  # returns `{:error, %Ash.Error.Unknown{}}` — a real, non-Forbidden error —
  # exercising `fetch/2`'s `raise error` clause specifically, rather than a
  # raise thrown by some unrelated internal path.
  defmodule ErroringCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck
    def describe(_opts), do: "always errors"
    def match?(_actor, _context, _opts), do: {:error, RuntimeError.exception("boom")}
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource KumiAdmin.MetricValueTest.Denied
      resource KumiAdmin.MetricValueTest.Erroring
    end
  end

  defmodule Denied do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy, create: :*, update: :*]
    end

    attributes do
      uuid_primary_key :id
      attribute :price, :decimal, public?: true
    end

    policies do
      policy always() do
        authorize_if DenyCheck
      end
    end
  end

  defmodule Erroring do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy, create: :*, update: :*]
    end

    attributes do
      uuid_primary_key :id
      attribute :price, :decimal, public?: true
    end

    policies do
      policy always() do
        authorize_if ErroringCheck
      end
    end
  end

  defp create_widget!(attrs) do
    Widget |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  describe "count metric" do
    test "returns the real record count, scoped to the actor" do
      create_widget!(%{})
      create_widget!(%{})

      metric = %Metric{kind: :count, resource: Widget}
      assert MetricValue.fetch(metric, nil) == {:ok, 2}
    end

    test "returns :forbidden when the read is policy-denied" do
      metric = %Metric{kind: :count, resource: Denied}
      assert MetricValue.fetch(metric, nil) == :forbidden
    end
  end

  describe "sum metric" do
    test "normalises a nil sum (no matching records) to 0" do
      # This is the assertion that fails if `{:ok, nil} -> {:ok, 0}` in
      # `MetricValue.fetch/2` is ever deleted — without it, this branch
      # returns `{:ok, nil}` and the dashboard renders a broken value.
      metric = %Metric{kind: :sum, resource: Widget, field: :price}
      assert MetricValue.fetch(metric, nil) == {:ok, 0}
    end

    test "returns the real sum when matching records exist" do
      create_widget!(%{price: Decimal.new("10")})
      create_widget!(%{price: Decimal.new("5")})

      metric = %Metric{kind: :sum, resource: Widget, field: :price}
      assert MetricValue.fetch(metric, nil) == {:ok, Decimal.new("15")}
    end

    test "returns :forbidden when the read is policy-denied" do
      metric = %Metric{kind: :sum, resource: Denied, field: :price}
      assert MetricValue.fetch(metric, nil) == :forbidden
    end
  end

  test "raises on any non-Forbidden error, instead of swallowing it" do
    metric = %Metric{kind: :count, resource: Erroring}

    assert_raise Ash.Error.Unknown, fn ->
      MetricValue.fetch(metric, nil)
    end
  end
end
