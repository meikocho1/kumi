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
    test "creates lib/my_app/core/attachment.ex with the marker fn and destroy after_transaction" do
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
      assert content =~ ~r/change\(?\s*after_transaction\(fn _changeset, result, _context ->/
      assert content =~ "KumiStorage.Upload.delete_stored(result, backend, backend_opts)"
      refute content =~ "after_action"
      assert content =~ "attribute :storage_key, :string"
      assert content =~ "attribute :content_type, :string"
      assert content =~ "attribute :byte_size, :integer"
    end

    test "storage_key is private: the key is all that protects a file's URL" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      content = Rewrite.Source.get(source, :content)

      assert content =~
               ~r/attribute :storage_key, :string do\s+allow_nil\?\(?\s*false\)?\s+public\?\(?\s*false\)?/
    end

    test "defines __kumi_storage_config__/0, the one place storage config is read" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      content = Rewrite.Source.get(source, :content)

      assert content =~ "def __kumi_storage_config__ do"
      assert content =~ "Application.fetch_env!(:kumi_storage, :backend)"
      # Both actions go through it; nothing else reads the config.
      assert length(Regex.scan(~r/__MODULE__\.__kumi_storage_config__\(\)/, content)) == 2
      assert length(Regex.scan(~r/Application\.fetch_env!/, content)) == 1
    end

    test "the fixtures' :upload and :destroy actions are the generated ones, verbatim" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      generated = source |> Rewrite.Source.get(:content) |> actions()

      fixture =
        Path.expand("../../support/test_attachment.ex", __DIR__) |> File.read!() |> actions()

      mnesia_fixture =
        Path.expand("../../support/mnesia_attachment.ex", __DIR__) |> File.read!() |> actions()

      assert Map.fetch!(fixture, :upload) == Map.fetch!(generated, :upload)
      assert Map.fetch!(fixture, :destroy) == Map.fetch!(generated, :destroy)
      assert Map.fetch!(mnesia_fixture, :upload) == Map.fetch!(generated, :upload)
    end

    test "generates the :upload create action delegating to KumiStorage.Upload.prepare/3" do
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
      # Still accepted (kumi_admin sends it), but optional and ignored.
      assert content =~ ~r/argument\(?\s*:byte_size,\s*:integer\)?\n/
      assert content =~ "KumiStorage.Upload.prepare(changeset, backend, backend_opts)"
      # The store moved into prepare/3's hook; the change body no longer
      # calls the backend or echoes a reason to the caller.
      refute content =~ "backend.store("
      refute content =~ "inspect(reason)"
      refute content =~ "blueprint"
    end

    test "the generated source parses, and its :upload change calls KumiStorage.Upload.prepare" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      ast = source |> Rewrite.Source.get(:content) |> Code.string_to_quoted!()

      {_ast, upload_calls} =
        Macro.prewalk(ast, [], fn
          {:create, _, [:upload, [do: body]]} = node, acc ->
            {node, acc ++ remote_calls(body)}

          node, acc ->
            {node, acc}
        end)

      assert {KumiStorage.Upload, :prepare, 3} in upload_calls
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

    test "adds the default upload root to .gitignore, keeping what was there" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      gitignore = igniter.rewrite |> Rewrite.source!(".gitignore") |> Rewrite.Source.get(:content)

      assert gitignore =~ ~r{^/priv/uploads/$}m
      assert gitignore =~ ~r{^/_build/$}m

      assert Enum.any?(igniter.notices, fn n ->
               IO.iodata_to_binary(n) =~ "config/runtime.exs"
             end)
    end

    test "running twice does not duplicate the .gitignore entry" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])
        |> apply_igniter!()

      igniter = Igniter.compose_task(igniter, "kumi_storage.install", [])

      assert_unchanged(igniter, ".gitignore")
    end
  end

  describe "router mount" do
    test "no router found: notice only" do
      igniter =
        test_project(app_name: :my_app)
        |> Igniter.compose_task("kumi_storage.install", [])

      notice =
        Enum.find_value(igniter.notices, fn n ->
          n = IO.iodata_to_binary(n)
          if n =~ "KumiStorage.Plug", do: n
        end)

      assert notice =~
               ~s(forward "/uploads", KumiStorage.Plug, config: {MyApp.Core.Attachment, :__kumi_storage_config__})

      assert notice =~ "public to anyone holding the URL"
    end

    test "router present: forwards KumiStorage.Plug with the Attachment's config function" do
      igniter =
        test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => @router})
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, source, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

      content = Rewrite.Source.get(source, :content)

      assert content =~
               ~r/forward\(?\s*"\/uploads",\s*KumiStorage\.Plug,\s*config:\s*\{MyApp\.Core\.Attachment,\s*:__kumi_storage_config__\}/

      assert Enum.any?(igniter.notices, fn n ->
               n = IO.iodata_to_binary(n)

               n =~ "mounted file serving at /uploads/:key" and
                 n =~ "public to anyone holding the URL"
             end)
    end

    test "the forward and the generated URL function use the same mount path" do
      igniter =
        test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => @router})
        |> Igniter.compose_task("kumi_storage.install", [])

      {_igniter, router, _zipper} = Igniter.Project.Module.find_module!(igniter, MyAppWeb.Router)

      {_igniter, attachment, _zipper} =
        Igniter.Project.Module.find_module!(igniter, MyApp.Core.Attachment)

      [_, mount] =
        Regex.run(
          ~r/forward\(?\s*"([^"]+)",\s*KumiStorage\.Plug/,
          Rewrite.Source.get(router, :content)
        )

      [_, url_prefix] =
        Regex.run(
          ~r/def __kumi_attachment_url__\(record\), do: "([^"#]*)\#\{record\.storage_key\}"/,
          Rewrite.Source.get(attachment, :content)
        )

      assert url_prefix == mount <> "/"
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

      assert igniter.warnings == []
    end

    test "a forward from before `config:` gets a warning with the replacement line" do
      old_router = """
      defmodule MyAppWeb.Router do
        use MyAppWeb, :router

        scope "/" do
          forward "/uploads", KumiStorage.Plug
        end
      end
      """

      igniter =
        test_project(app_name: :my_app, files: %{"lib/my_app_web/router.ex" => old_router})
        |> Igniter.compose_task("kumi_storage.install", [])

      assert_unchanged(igniter, "lib/my_app_web/router.ex")

      assert Enum.any?(igniter.warnings, fn w ->
               IO.iodata_to_binary(w) =~
                 ~s(forward "/uploads", KumiStorage.Plug, config: {MyApp.Core.Attachment, :__kumi_storage_config__})
             end)
    end
  end

  describe "an Attachment that predates __kumi_storage_config__/0" do
    test "gets a warning naming the function the forward calls" do
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

      assert Enum.any?(igniter.warnings, fn w ->
               IO.iodata_to_binary(w) =~ "has no __kumi_storage_config__/0"
             end)
    end
  end

  # `%{action_name => body}` for the create/destroy actions in `source`,
  # with line/column metadata stripped so formatting doesn't matter.
  defp actions(source) do
    {_ast, actions} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(%{}, fn
        {type, _, [name, [do: body]]} = node, acc when type in [:create, :destroy] ->
          {node, Map.put(acc, name, Macro.prewalk(body, &Macro.update_meta(&1, fn _ -> [] end)))}

        node, acc ->
          {node, acc}
      end)

    actions
  end

  # `{Module, :fun, arity}` for every `Module.fun(...)` call inside `ast`.
  defp remote_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, args} = node, acc when is_list(args) ->
          {node, [{Module.concat(parts), fun, length(args)} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end
end
