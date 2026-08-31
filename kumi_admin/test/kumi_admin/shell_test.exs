defmodule KumiAdmin.ShellTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  defmodule App do
    use Kumi.App

    app do
      name :shell_test
      title("Shell Test")
    end
  end

  defp page(assigns) do
    ~H"""
    <KumiAdmin.Components.Shell.shell
      app={App}
      text={KumiAdmin.Text.new(App)}
      mount_path="/admin"
      actor={@actor}
    >
      body-content
    </KumiAdmin.Components.Shell.shell>
    """
  end

  test "shell emits its stylesheet as real CSS, not escaped/literal HEEx text" do
    html = render_component(&page/1, %{actor: nil})

    # HEEx disables `{...}` interpolation inside <style>; a regression there
    # ships the literal source text and the admin renders completely unstyled.
    assert html =~ ".kumi-admin-shell {"
    assert html =~ "display: flex"
    refute html =~ "{css()}"
    assert html =~ "body-content"

    # This substring contains literal double quotes. HTML-escaping (i.e.
    # dropping `Phoenix.HTML.raw/1` around `css()`) would turn them into
    # `&quot;`, which the two assertions above can't detect — the rest of
    # this CSS has no `<`, `>`, or `&` characters for escaping to alter.
    assert html =~ ~s(font-family: system-ui, -apple-system, "Segoe UI", sans-serif;)
  end

  test "footer carries the Kumi mark and attribution" do
    html = render_component(&page/1, %{actor: nil})

    assert html =~ "Powered by Kumi"
    assert html =~ ~s(aria-label="Kumi")
  end

  # Note: class *names* (e.g. "kumi-admin-signout") always appear somewhere
  # in the emitted <style> block regardless of the actor, since the CSS
  # rules are static — assertions below match the rendered markup
  # (`class="..."` / element text), not the bare class name substring.

  test "topbar shows actor email and sign-out link when an actor is present" do
    html = render_component(&page/1, %{actor: %{email: "person@example.com"}})

    assert html =~ "person@example.com"
    assert html =~ ~s(class="kumi-admin-signout")
    assert html =~ "Sign out"
  end

  test "topbar shows neither sign-out nor sign-in when actor is nil" do
    # The gate (KumiAdmin.Gate) redirects actor-less mounts before the
    # shell ever renders in the app — this component-level render is the
    # only place that scenario is still exercised, defensively.
    html = render_component(&page/1, %{actor: nil})

    refute html =~ ~s(class="kumi-admin-signout")
    refute html =~ "Sign out"
    refute html =~ "Sign in"
  end

  test "topbar handles an actor with no email field defensively" do
    html = render_component(&page/1, %{actor: %{id: 1}})

    assert html =~ ~s(class="kumi-admin-signout")
    refute html =~ ~s(class="kumi-admin-topbar-email")
  end
end
