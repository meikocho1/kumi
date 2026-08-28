defmodule KumiAdmin.StageCountsTest do
  @moduledoc """
  `KumiAdmin.StageCounts.fetch/2` has no injectable seam — each stage runs
  a real `Ash.count/2` against the `Workflow`'s resource — so the
  short-circuit branch is exercised against a real Ash resource (in-memory
  `Ash.DataLayer.Ets`) with a real `Ash.Policy.Authorizer` policy that
  denies unconditionally. `Kumi.App.Dsl.Workflow` is a plain struct, so
  it's constructed directly without going through the `Kumi.App` DSL macro.
  """

  use ExUnit.Case, async: true

  alias Kumi.App.Dsl.Workflow
  alias KumiAdmin.StageCounts
  alias KumiAdmin.Test.Widget

  defmodule DenyCheck do
    @moduledoc false
    use Ash.Policy.SimpleCheck
    def describe(_opts), do: "always denies"
    def match?(_actor, _context, _opts), do: false
  end

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource KumiAdmin.StageCountsTest.Denied
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
      attribute :stage, :atom, public?: true, constraints: [one_of: [:new, :active, :done]]
    end

    policies do
      policy always() do
        authorize_if DenyCheck
      end
    end
  end

  defp create_widget!(attrs) do
    Widget |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  test "returns real per-stage counts, in declared stage order" do
    create_widget!(%{status: :draft})
    create_widget!(%{status: :draft})
    create_widget!(%{status: :published})

    workflow = %Workflow{resource: Widget, field: :status, stages: [:draft, :published]}
    assert StageCounts.fetch(workflow, nil) == {:ok, [draft: 2, published: 1]}
  end

  test "a stage with zero matching records reports 0 rather than being omitted" do
    create_widget!(%{status: :published})

    workflow = %Workflow{resource: Widget, field: :status, stages: [:draft, :published]}
    assert StageCounts.fetch(workflow, nil) == {:ok, [draft: 0, published: 1]}
  end

  test "a policy-forbidden read short-circuits the whole workflow to :forbidden, not partial counts" do
    workflow = %Workflow{resource: Denied, field: :stage, stages: [:new, :active, :done]}

    # If the `reduce_while` halt in `StageCounts.fetch/2` were ever replaced
    # by logic that collects whatever succeeds and skips/zeroes failures,
    # this would come back as `{:ok, [...]}` instead of the bare
    # `:forbidden` atom the module documents.
    assert StageCounts.fetch(workflow, nil) == :forbidden
  end
end
