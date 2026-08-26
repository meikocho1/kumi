defmodule KumiAdmin.Format do
  @moduledoc """
  Cell/field rendering for the generic table and detail page: truncate
  `id`, shorten datetimes, spell out `nil`. Everything else falls back to
  `to_string/1` (covers `Decimal`, plain strings, integers, atoms via
  `String.Chars`).
  """

  @id_prefix_length 8

  @doc "Renders a single attribute value for display, keyed by attribute name."
  @spec cell(atom(), term()) :: String.t()
  def cell(:id, value) when is_binary(value), do: truncate_id(value)
  def cell(_key, %DateTime{} = value), do: short_datetime(value)
  def cell(_key, %NaiveDateTime{} = value), do: short_datetime(value)
  def cell(_key, nil), do: "—"
  def cell(_key, value) when is_atom(value), do: Atom.to_string(value)
  def cell(_key, value), do: to_string(value)

  @doc "Truncates a UUID-shaped id to its first #{@id_prefix_length} characters."
  @spec truncate_id(String.t()) :: String.t()
  def truncate_id(id) when byte_size(id) > @id_prefix_length do
    String.slice(id, 0, @id_prefix_length) <> "…"
  end

  def truncate_id(id), do: id

  @doc "Formats a datetime as `YYYY-MM-DD HH:MM`."
  @spec short_datetime(DateTime.t() | NaiveDateTime.t()) :: String.t()
  def short_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")

  @doc """
  A human label for a record: its `:name` field when present and
  non-blank, else its (truncated) id. Same "name-ish field else id"
  heuristic used for `belongs_to` display on the detail page and for
  `belongs_to` select options on the form.
  """
  @spec record_label(struct()) :: String.t()
  def record_label(record) do
    case Map.get(record, :name) do
      name when is_binary(name) and name != "" -> name
      _ -> truncate_id(record.id)
    end
  end
end
