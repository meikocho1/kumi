defmodule Mix.Tasks.KumiStorage.InstallTest do
  @moduledoc """
  `mix kumi_storage.install` composes `kumi.install`, then generates a
  plain-Ash Attachment resource (blueprint §6 point 1: D1 "Show Ash" — the
  generated source must show exactly what compiles, so this asserts on
  the generated string content, not just that a file exists), configures
  the Local backend, and forwards `KumiStorage.Plug` in the host router.
  """
  use ExUnit.Case, async: true

  import Igniter.Test

  @router """
  defmodule MyAppWeb.Router do
    use MyAppWeb, :router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/", MyAppWeb do
      pipe_through :browser

      get "/", PageController, :home
    end
  end
  """

  describe "Attachment resource generation" do
    test "creates lib/my_app/core/attachment.ex with the marker fn and destroy after_action" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      assert_creates(igniter, "lib/my_app/core/attachment.ex")

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      content = Rewrite.Source.get(source, :content)

      assert content =~ "use Ash.Resource,"
      assert content =~ "domain: MyApp.Core"
      assert content =~ ~r/table\(?\s*"attachments"/
      assert content =~ "def __kumi_attachment__, do: true"

      assert content =~
               "def __kumi_attachment_url__(record), do: \"/uploads/\#{record.storage_key}\""

      assert content =~ "destroy :destroy do"
      assert content =~ ~r/require_atomic\?\(?\s*false\)?/
      assert content =~ "backend.delete(record.storage_key"
      assert content =~ "attribute :storage_key, :string"
      assert content =~ "attribute :content_type, :string"
      assert content =~ "attribute :byte_size, :integer"
    end

    test "generates the :upload create action calling Validation then the backend's store/4" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      content = Rewrite.Source.get(source, :content)

      assert content =~ "create :upload do"
      assert content =~ ~r/argument\(?\s*:source,\s*:term,\s*allow_nil\?:\s*false\)?/
      assert content =~ ~r/argument\(?\s*:filename,\s*:string,\s*allow_nil\?:\s*false\)?/
      assert content =~ ~r/argument\(?\s*:content_type,\s*:string,\s*allow_nil\?:\s*false\)?/
      assert content =~ ~r/argument\(?\s*:byte_size,\s*:integer,\s*allow_nil\?:\s*false\)?/
      assert content =~ "KumiStorage.Validation.validate("
      assert content =~ "backend.store(source, filename, content_type, backend_opts)"
      assert content =~ "force_change_attribute(:storage_key, storage_key)"
      assert content =~ ":too_large"
      assert content =~ ":disallowed_content_type"
    end

    test "registers Attachment in the Core domain's resources" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} = Igniter.Project.Module.find_module!(igniter, MyApp.Core)
      content = Rewrite.Source.get(source, :content)

      assert content =~ "MyApp.Core.Attachment"
    end

    test "existing Attachment module is left untouched" do
      igniter =
        test_project(
          app_name: :my_app,
          files: %{
            "lib/my_app/core/attachment.ex" => """
            defmodule MyApp.Core.Attachment do
              def __kumi_attachment__, do: true
            end
            """
          }
        )
        |> Igniter.compose_task("kumi_storage.install", [])

      assert_unchanged(igniter, "lib/my_app/core/attachment.ex")

      assert Enum.any?(igniter.notices, fn n ->
               IO.iodata_to_binary(n) =~ "already exists"
             end)
    end

    test "running twice does not duplicate the resource or the domain registration" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])
        |> apply_igniter!()

      igniter = Igniter.compose_task(igniter, "kumi_storage.install", [])

      assert_unchanged(igniter, "lib/my_app/core/attachment.ex")
      assert_unchanged(igniter, "lib/my_app/core.ex")
    end
  end

  describe "backend config" do
    test "adds the Local backend + root config when absent" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      config_content =
        igniter.rewrite
        |> Rewrite.source!("config/config.exs")
        |> Rewrite.Source.get(:content)

      assert config_content =~ "config :kumi_storage"
      assert config_content =~ "KumiStorage.Backend.Local"
      assert config_content =~ "priv/uploads"
    end

    test "running twice does not duplicate the config" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])
        |> apply_igniter!()

      igniter = Igniter.compose_task(igniter, "kumi_storage.install", [])

      config_content =
        igniter.rewrite
        |> Rewrite.source!("config/config.exs")
        |> Rewrite.Source.get(:content)

      assert length(Regex.scan(~r/KumiStorage\.Backend\.Local/, config_content)) == 1
    end
  end

  describe "router mount" do
    test "no router found: notice only" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      assert Enum.any?(igniter.notices, fn n ->
               IO.iodata_to_binary(n) =~ "KumiStorage.Plug"
             end)
    end

    test "router present: forwards KumiStorage.Plug" do
      igniter =
        test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => @router})
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

      content = Rewrite.Source.get(source, :content)
      assert content =~ ~r/forward\(?\s*"\/uploads",\s*KumiStorage\.Plug/
    end

    test "running twice does not duplicate the mount" do
      igniter =
        test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => @router})
        |> Igniter.compose_task("kumi_storage.install", [])
        |> apply_igniter!()

      igniter = Igniter.compose_task(igniter, "kumi_storage.install", [])

      assert_unchanged(igniter, "lib/my_app_web/router.ex")

      assert Enum.any?(igniter.notices, fn n ->
               IO.iodata_to_binary(n) =~ "already mounted"
             end)
    end
  end
end
