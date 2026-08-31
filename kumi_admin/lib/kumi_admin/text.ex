defmodule KumiAdmin.Text do
  @moduledoc """
  Every piece of display text the admin renders, resolved once per mount
  and carried through the LiveViews as a single `text` assign.

  Two kinds of text, one struct, because both answers come from the same
  `Kumi.App` module and neither should be looked up again on every render:

    * **chrome** — the admin's own fixed strings (`New`, `Search…`,
      `No access.`), from `KumiAdmin.Locale` in the app's declared locale
    * **labels** — what the app's own resources, attributes, workflows,
      stages and metrics are called, from `admin do labels %{...} end`,
      in whatever language the author wrote them

  A term with no declared label falls back to exactly what the admin
  rendered before labels existed — `KumiAdmin.Label.plural/1` for a
  resource, `Phoenix.Naming.humanize/1` for a field, the bare name for a
  workflow, stage, dashboard or metric — so an app that declares nothing
  renders byte-identically to before.
  """

  alias Kumi.App.Info

  @enforce_keys [:locale, :labels, :strings]
  defstruct [:locale, :labels, :strings]

  @type t :: %__MODULE__{
          locale: Kumi.Locale.locale(),
          labels: map(),
          strings: Kumi.Locale.table()
        }

  @doc """
  Resolves an app's text once.

  `overrides` replaces individual chrome strings per locale
  (`%{ja: %{new: "登録"}}`) — a host that wants different wording swaps
  the string, it doesn't fork the table.
  """
  @spec new(module(), map()) :: t()
  def new(app, overrides \\ %{}) do
    %__MODULE__{
      locale: Info.locale(app),
      labels: Info.labels(app),
      strings: Kumi.Locale.merge(KumiAdmin.Locale.table(), overrides)
    }
  end

  @doc "One of the admin's own chrome strings, with `%{binding}` values filled in."
  @spec string(t(), atom(), keyword() | map()) :: String.t()
  def string(%__MODULE__{} = text, key, bindings \\ []) do
    Kumi.Locale.translate(text.strings, text.locale, key, bindings)
  end

  @doc """
  What to call a resource in a heading or a nav link — the declared label,
  else the pluralized module name.

  A declared label is used verbatim: no pluralization pass, because most
  languages don't form a plural by appending `s` and the author already
  wrote the form they wanted.
  """
  @spec resource(t(), module()) :: String.t()
  def resource(%__MODULE__{} = text, resource) do
    Map.get(text.labels, resource) || KumiAdmin.Label.plural(resource)
  end

  @doc "What to call one attribute or relationship of a resource."
  @spec field(t(), module(), atom()) :: String.t()
  def field(%__MODULE__{} = text, resource, name) do
    Map.get(text.labels, {resource, name}) || Phoenix.Naming.humanize(name)
  end

  @doc """
  What to call a workflow or a dashboard.

  The fallback is the name as declared, not a humanized version of it:
  the dashboard has always printed `deal_count` and `lead` verbatim, and
  adding labels is not the place to change what an app that declares none
  of them renders.
  """
  @spec term(t(), atom()) :: String.t()
  def term(%__MODULE__{} = text, name) do
    Map.get(text.labels, name) || to_string(name)
  end

  @doc "What to call one stage of a workflow, or one metric of a dashboard."
  @spec term(t(), atom(), atom()) :: String.t()
  def term(%__MODULE__{} = text, scope, key) do
    Map.get(text.labels, {scope, key}) || to_string(key)
  end
end
