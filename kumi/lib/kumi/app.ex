defmodule Kumi.App do
  @moduledoc """
  Application-level DSL — blueprint §3's "two-layer DSL ownership". Kumi.App
  owns app-level intent ONLY: which Ash resources make up the product, admin
  navigation, workflows, dashboards, and app metadata. It never duplicates
  Ash's domain-level DSL (attributes/actions/relationships/policies) —
  resources referenced here stay plain, standard `Ash.Resource` modules.

      defmodule MyApp.App do
        use Kumi.App

        app do
          name :crm
          title "Mini CRM"
        end

        resources do
          resource MyApp.Account
          resource MyApp.Contact
          resource MyApp.Deal
        end

        admin do
          navigation [MyApp.Account, MyApp.Contact, MyApp.Deal]
        end

        workflow :sales_pipeline do
          stages [:lead, :qualified, :proposal, :won, :lost]
        end

        dashboard :overview do
          metric :pipeline_value
          metric :conversion_rate
        end
      end

  Everything declared here is introspectable via `Kumi.App.Info` —
  "explainable magic" (blueprint §3): no behavior lives only in a macro
  expansion you can't read back out.
  """

  use Spark.Dsl, default_extensions: [extensions: [Kumi.App.Dsl]]
end
