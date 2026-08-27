defmodule KumiNew.InjectTest do
  use ExUnit.Case, async: true

  alias KumiNew.Inject

  @fixtures_dir Path.join(__DIR__, "../fixtures")
  @mix_exs File.read!(Path.join(@fixtures_dir, "generated_mix.exs"))
  @dev_exs File.read!(Path.join(@fixtures_dir, "generated_dev.exs"))
  @test_exs File.read!(Path.join(@fixtures_dir, "generated_test_config.exs"))

  describe "insert_deps/3" do
    test "inserts kumi and kumi_admin as the first deps, admin? true" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", true)
      assert updated =~ ~s[{:kumi, path: "/abs/kumi_path/kumi"}]
      assert updated =~ ~s[{:kumi_admin, path: "/abs/kumi_path/kumi_admin"}]

      # kumi comes before the existing deps, kumi_admin comes right after kumi
      [_, rest] = String.split(updated, ~s[{:kumi, path:])
      assert rest =~ ~s[{:kumi_admin, path:]

      # existing deps list is untouched otherwise
      assert updated =~ ~s[{:bcrypt_elixir, "~> 3.0"}]
    end

    test "omits kumi_admin when admin? is false" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", false)
      assert updated =~ ~s[{:kumi, path: "/abs/kumi_path/kumi"}]
      refute updated =~ "kumi_admin"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", true)
      assert {:ok, _quoted} = Code.string_to_quoted(updated)
    end

    test "errors loudly when the anchor is absent" do
      assert {:error, message} = Inject.insert_deps("defmodule Foo do\nend\n", "/x", true)
      assert message =~ "could not find"
    end

    test "adds a path dep for each selected optional module, after kumi/kumi_admin" do
      assert {:ok, updated} =
               Inject.insert_deps(@mix_exs, "/abs/kumi_path", true, [:storage])

      assert updated =~ ~s[{:kumi_storage, path: "/abs/kumi_path/kumi_storage"}]

      # order: kumi, then kumi_admin, then the module dep
      [_, rest] = String.split(updated, ~s[{:kumi_admin, path:])
      assert rest =~ ~s[{:kumi_storage, path:]
    end

    test "works with modules even when admin? is false" do
      assert {:ok, updated} =
               Inject.insert_deps(@mix_exs, "/abs/kumi_path", false, [:storage])

      refute updated =~ "kumi_admin"
      assert updated =~ ~s[{:kumi_storage, path: "/abs/kumi_path/kumi_storage"}]
    end

    test "modules default to [] when omitted" do
      assert {:ok, updated} = Inject.insert_deps(@mix_exs, "/abs/kumi_path", true)
      refute updated =~ "kumi_storage"
    end
  end

  describe "patch_port/2" do
    test "inserts port: PORT right after hostname in dev.exs" do
      assert {:ok, updated} = Inject.patch_port(@dev_exs, 5434)
      assert updated =~ "hostname: \"localhost\",\n  port: 5434,\n"
    end

    test "inserts port: PORT right after hostname in test.exs" do
      assert {:ok, updated} = Inject.patch_port(@test_exs, 5434)
      assert updated =~ "hostname: \"localhost\",\n  port: 5434,\n"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, updated} = Inject.patch_port(@dev_exs, 5434)
      assert {:ok, _quoted} = Code.string_to_quoted(updated)
    end

    test "errors loudly when the anchor is absent" do
      assert {:error, message} = Inject.patch_port("config :x, Y, []\n", 5434)
      assert message =~ "could not find"
    end
  end

  describe "home_page/2" do
    test "with admin? true: brands the hero with title, admin, and sign-in links, mark in footer" do
      html = Inject.home_page("My Crm", true)

      assert html =~ "My Crm"
      assert html =~ ~s(href="/kumi-admin")
      assert html =~ ~s(href="/sign-in")
      assert html =~ "Powered by Kumi"
      assert html =~ ~s(aria-label="Kumi")
      # no leftover phx.new marketing copy
      refute html =~ "Peace of mind from prototype to production"
    end

    test "with admin? false: no /kumi-admin link, sign-in becomes the primary action" do
      html = Inject.home_page("My Crm", false)

      refute html =~ "/kumi-admin"
      assert html =~ ~s(href="/sign-in" class="kumi-top-button kumi-top-button-primary")
    end
  end

  describe "auth_overrides/2" do
    test "defines <web_module>.AuthOverrides restyled with the given title and Kumi mark" do
      content = Inject.auth_overrides("MyCrmWeb", "My Crm")

      assert content =~ "defmodule MyCrmWeb.AuthOverrides do"
      assert content =~ "use AshAuthentication.Phoenix.Overrides"
      assert content =~ ~s(set :text, "My Crm")
      assert content =~ "data:image/svg+xml;base64,"
      assert content =~ "override Components.Password.Input do"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, _quoted} =
               Code.string_to_quoted(Inject.auth_overrides("MyCrmWeb", "My Crm"))
    end
  end

  describe "page_controller_test/1" do
    test "asserts the branded home page copy, not phx.new's default" do
      content = Inject.page_controller_test("MyCrmWeb")

      assert content =~ "defmodule MyCrmWeb.PageControllerTest do"
      assert content =~ "use MyCrmWeb.ConnCase"
      assert content =~ "assert html_response(conn, 200) =~ \"Built with Kumi.\""
      refute content =~ "Peace of mind from prototype to production"
    end

    test "the result is still valid Elixir (parses)" do
      assert {:ok, _quoted} = Code.string_to_quoted(Inject.page_controller_test("MyCrmWeb"))
    end
  end
end
