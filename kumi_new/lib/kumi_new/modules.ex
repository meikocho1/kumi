defmodule KumiNew.Modules do
  @moduledoc """
  The optional-module catalog for `mix kumi.new` and pure parsing of module
  selections (`--with`, the interactive prompt answer). Hardcoded module
  attribute list — zero-dep, no registry framework — because the catalog is
  small and changes rarely; adding `mail`/`chat` later is one entry.

  `admin` is NOT in this catalog: it's the default product shell, controlled
  by the existing `--no-admin` flag, not an optional add-on offered here.

  Only `catalog/0`, `keys/0`, `describe_catalog/0`, `parse_selection/1`, and
  `prompt_text/0` are pure. `interactive?/0` and `resolve/1` touch `Mix.shell()`
  / `IO.ANSI` and are exercised only by the real `mix kumi.new` run, not unit
  tests.
  """

  defmodule Entry do
    @moduledoc "One optional-module catalog entry."
    defstruct [:key, :description, :dep, :installer]

    @type t :: %__MODULE__{
            key: atom(),
            description: String.t(),
            dep: atom(),
            installer: String.t()
          }
  end

  # A plain module attribute holding `%Entry{}` structs can't be evaluated
  # here — `Entry` is still compiling as part of this same module. Built
  # lazily by `catalog/0` instead, once at call time.
  @spec catalog() :: [Entry.t()]
  def catalog do
    [
      %Entry{
        key: :storage,
        description: "File/image uploads (kumi_storage)",
        dep: :kumi_storage,
        installer: "kumi_storage.install"
      }
    ]
  end

  @spec keys() :: [atom()]
  def keys, do: Enum.map(catalog(), & &1.key)

  @spec fetch(atom()) :: Entry.t() | nil
  def fetch(key), do: Enum.find(catalog(), &(&1.key == key))

  @spec describe_catalog() :: String.t()
  def describe_catalog do
    Enum.map_join(catalog(), "\n", fn e -> "  #{e.key} — #{e.description} (default: off)" end)
  end

  @doc "The bracketed hint lists the catalog's keys, e.g. `[storage]`."
  @spec prompt_text() :: String.t()
  def prompt_text do
    "Modules to include (comma-separated, empty for none) [#{Enum.join(keys(), ",")}]: "
  end

  @doc """
  Parses a comma-separated module selection (from `--with` or the
  interactive prompt answer). Empty/blank input selects nothing. Unknown
  keys fail loudly, naming the catalog so the caller knows what's valid.
  """
  @spec parse_selection(String.t()) :: {:ok, [atom()]} | {:error, String.t()}
  def parse_selection(str) when is_binary(str) do
    tokens =
      str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {found, unknown} =
      Enum.reduce(tokens, {[], []}, fn token, {found, unknown} ->
        case Enum.find(catalog(), &(to_string(&1.key) == token)) do
          nil -> {found, [token | unknown]}
          entry -> {[entry.key | found], unknown}
        end
      end)

    case Enum.reverse(unknown) do
      [] ->
        {:ok, found |> Enum.reverse() |> Enum.uniq()}

      bad ->
        {:error,
         "unknown module(s): #{Enum.join(bad, ", ")}. Available modules:\n" <>
           describe_catalog()}
    end
  end

  @doc """
  True only when we're confident a human is at the keyboard: `Mix.shell()`
  is still the default IO shell (not `Mix.Shell.Process` under test, not
  swapped for a quiet/CI shell) and the terminal reports ANSI support. Any
  doubt (piped input, CI, agent runs) resolves to false — the picker must
  never hang a non-interactive run.
  """
  @spec interactive?() :: boolean()
  def interactive? do
    Mix.shell() == Mix.Shell.IO and IO.ANSI.enabled?()
  end

  @doc """
  Resolves a parsed `t:KumiNew.Args.modules_flag/0` into the final module
  list. `{:with, list}` and `:none` are already decided — no I/O. `:unset`
  prompts interactively when the shell allows it, otherwise defaults to no
  optional modules.
  """
  @spec resolve({:with, [atom()]} | :none | :unset) :: {:ok, [atom()]} | {:error, String.t()}
  def resolve({:with, list}), do: {:ok, list}
  def resolve(:none), do: {:ok, []}

  def resolve(:unset) do
    if interactive?() do
      Mix.shell().info("\nOptional Kumi modules:\n" <> describe_catalog())

      case Mix.shell().prompt(prompt_text()) do
        answer when is_binary(answer) -> parse_selection(String.trim(answer))
        # :eof — stdin closed/piped despite looking interactive; don't crash.
        _ -> {:ok, []}
      end
    else
      {:ok, []}
    end
  end
end
