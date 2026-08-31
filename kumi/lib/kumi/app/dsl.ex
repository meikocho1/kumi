defmodule Kumi.App.Dsl do
  @moduledoc """
  The `Spark.Dsl.Extension` behind `Kumi.App` — blueprint §3's app-level
  layer: name/title, which Ash resources belong to the product, admin
  navigation, workflows, and dashboards. Deliberately does not (and must
  not) grow attribute/action/policy-shaped options — that's Ash's DSL, one
  layer down. See `Kumi.App` for the user-facing shape.
  """

  defmodule Resource do
    @moduledoc "A single `resource ModuleName` entry inside a `resources do ... end` block."
    defstruct [:resource, :__spark_metadata__]
    @type t :: %__MODULE__{resource: module(), __spark_metadata__: term()}
  end

  defmodule Metric do
    @moduledoc "A single `metric :name, resource: ...` entry inside a `dashboard do ... end` block."
    defstruct [:name, :resource, :field, :__spark_metadata__, kind: :count]

    @type t :: %__MODULE__{
            name: atom(),
            resource: module(),
            kind: :count | :sum,
            field: atom() | nil,
            __spark_metadata__: term()
          }
  end

  defmodule Workflow do
    @moduledoc "A top-level `workflow :name do ... end` entry."
    defstruct [:name, :resource, :field, :__spark_metadata__, stages: []]

    @type t :: %__MODULE__{
            name: atom(),
            resource: module(),
            field: atom(),
            stages: [atom()],
            __spark_metadata__: term()
          }
  end

  defmodule Dashboard do
    @moduledoc "A top-level `dashboard :name do ... end` entry."
    defstruct [:name, :__spark_metadata__, metrics: []]
    @type t :: %__MODULE__{name: atom(), metrics: [Metric.t()], __spark_metadata__: term()}
  end

  @app %Spark.Dsl.Section{
    name: :app,
    describe: "App-level metadata.",
    examples: [
      """
      app do
        name :crm
        title "Mini CRM"
      end
      """
    ],
    schema: [
      name: [type: :atom, required: true, doc: "Machine-readable app identifier."],
      title: [type: :string, doc: "Human-readable app title, e.g. for admin UI chrome."],
      locale: [
        type: :atom,
        default: :en,
        doc:
          "Language for admin chrome and CLI output. One of `Kumi.Locale.locales/0`. " <>
            "Does not affect `--json` output, which is always English."
      ]
    ]
  }

  @resource %Spark.Dsl.Entity{
    name: :resource,
    describe: "An Ash resource this app exposes.",
    examples: ["resource MyApp.Account"],
    target: Resource,
    args: [:resource],
    schema: [
      resource: [type: :module, required: true, doc: "The `Ash.Resource` module."]
    ]
  }

  @resources %Spark.Dsl.Section{
    name: :resources,
    describe: "The Ash resources that make up this app.",
    entities: [@resource],
    examples: [
      """
      resources do
        resource MyApp.Account
      end
      """
    ]
  }

  @admin %Spark.Dsl.Section{
    name: :admin,
    describe: "Admin UI configuration.",
    examples: ["admin do\n  navigation [MyApp.Account]\n  related_limit 10\nend"],
    schema: [
      navigation: [
        type: {:list, :module},
        default: [],
        doc: "Resources shown in the admin nav, in order. Must be a subset of `resources`."
      ],
      related_limit: [
        type: :pos_integer,
        default: 10,
        doc: "Max child rows shown per has_many section on a detail page."
      ],
      labels: [
        # `:any`, not `:map`: Spark's `:map` requires atom keys, and half of
        # these keys are `{scope, key}` tuples. Shape and content are checked
        # by `Kumi.App.Verifiers.ValidateLabels`, which can say which key is
        # wrong and what the alternatives were.
        type: :any,
        default: %{},
        doc: """
        Display text for the things this app declares, in whatever language
        you want — free-form strings, not translation keys.

        A module or atom key labels a whole term (a resource, a workflow, a
        dashboard). A `{scope, key}` tuple labels something inside one: an
        attribute or relationship of a resource, a stage of a workflow, a
        metric of a dashboard.

            labels %{
              MyApp.Account => "アカウント",
              {MyApp.Account, :inserted_at} => "登録日",
              :sales_pipeline => "商談パイプライン",
              {:sales_pipeline, :lead} => "見込み",
              {:overview, :deal_count} => "商談数"
            }

        Anything not listed here falls back to the derived English label.
        """
      ]
    ]
  }

  @metric %Spark.Dsl.Entity{
    name: :metric,
    describe: "A single metric shown on a dashboard.",
    examples: ["metric :pipeline_value, resource: MyApp.Deal, kind: :sum, field: :amount"],
    target: Metric,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      resource: [type: :module, required: true, doc: "Ash resource this metric reads."],
      kind: [type: {:in, [:count, :sum]}, default: :count],
      field: [
        type: :atom,
        doc: "Summed attribute; required when kind is :sum, forbidden for :count."
      ]
    ]
  }

  @workflow %Spark.Dsl.Entity{
    name: :workflow,
    describe: "A named multi-stage workflow this app implements.",
    examples: [
      "workflow :sales_pipeline, resource: MyApp.Deal, field: :stage, stages: [:lead, :won]"
    ],
    target: Workflow,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      resource: [
        type: :module,
        required: true,
        doc: "Ash resource whose records move through these stages."
      ],
      field: [
        type: :atom,
        required: true,
        doc: "Public attribute on `resource` holding the current stage."
      ],
      stages: [type: {:list, :atom}, default: [], doc: "Ordered stage names."]
    ]
  }

  @workflows %Spark.Dsl.Section{
    name: :workflows,
    describe: "Workflows this app implements.",
    top_level?: true,
    entities: [@workflow]
  }

  @dashboard %Spark.Dsl.Entity{
    name: :dashboard,
    describe: "A named dashboard made of metrics.",
    examples: ["dashboard :overview do\n  metric :deal_count, resource: MyApp.Deal\nend"],
    target: Dashboard,
    args: [:name],
    entities: [metrics: [@metric]],
    schema: [name: [type: :atom, required: true]]
  }

  @dashboards %Spark.Dsl.Section{
    name: :dashboards,
    describe: "Dashboards this app exposes.",
    top_level?: true,
    entities: [@dashboard]
  }

  @sections [@app, @resources, @admin, @workflows, @dashboards]

  @verifiers [
    Kumi.App.Verifiers.ValidateAppName,
    Kumi.App.Verifiers.ValidateResources,
    Kumi.App.Verifiers.ValidatePrimaryKey,
    Kumi.App.Verifiers.ValidateNavigation,
    Kumi.App.Verifiers.ValidateWorkflowStages,
    Kumi.App.Verifiers.ValidateDashboardMetrics,
    Kumi.App.Verifiers.ValidateUniqueNames,
    Kumi.App.Verifiers.ValidateLocale,
    Kumi.App.Verifiers.ValidateLabels
  ]

  use Spark.Dsl.Extension, sections: @sections, verifiers: @verifiers
end
