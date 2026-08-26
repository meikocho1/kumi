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
    @moduledoc "A single `metric :name` entry inside a `dashboard do ... end` block."
    defstruct [:name, :__spark_metadata__]
    @type t :: %__MODULE__{name: atom(), __spark_metadata__: term()}
  end

  defmodule Workflow do
    @moduledoc "A top-level `workflow :name do ... end` entry."
    defstruct [:name, :__spark_metadata__, stages: []]
    @type t :: %__MODULE__{name: atom(), stages: [atom()], __spark_metadata__: term()}
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
      title: [type: :string, doc: "Human-readable app title, e.g. for admin UI chrome."]
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
    examples: ["admin do\n  navigation [MyApp.Account]\nend"],
    schema: [
      navigation: [
        type: {:list, :module},
        default: [],
        doc: "Resources shown in the admin nav, in order. Must be a subset of `resources`."
      ]
    ]
  }

  @metric %Spark.Dsl.Entity{
    name: :metric,
    describe: "A single metric shown on a dashboard.",
    examples: ["metric :pipeline_value"],
    target: Metric,
    args: [:name],
    schema: [name: [type: :atom, required: true]]
  }

  @workflow %Spark.Dsl.Entity{
    name: :workflow,
    describe: "A named multi-stage workflow this app implements.",
    examples: ["workflow :sales_pipeline do\n  stages [:lead, :won]\nend"],
    target: Workflow,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
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
    examples: ["dashboard :overview do\n  metric :pipeline_value\nend"],
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
    Kumi.App.Verifiers.ValidateResources,
    Kumi.App.Verifiers.ValidateNavigation,
    Kumi.App.Verifiers.ValidateWorkflowStages,
    Kumi.App.Verifiers.ValidateDashboardMetrics,
    Kumi.App.Verifiers.ValidateUniqueNames
  ]

  use Spark.Dsl.Extension, sections: @sections, verifiers: @verifiers
end
