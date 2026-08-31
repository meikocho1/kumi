defmodule KumiAdmin.Format do
  @moduledoc """
  Cell/field rendering for the generic table and detail page: truncate
  `id` and foreign keys, shorten datetimes, spell out `nil`. Everything
  else falls back to `to_string/1` (covers `Decimal`, plain strings,
  integers, atoms via `String.Chars`).
  """

  @id_prefix_length 8

  @doc """
  Renders a single attribute value for display, keyed by attribute name.

  `foreign_keys` names the attributes that back a `belongs_to` (see
  `KumiAdmin.Attributes.foreign_keys/1`); those are truncated, because
  rendering a full UUID pushes every other column out of the way and
  wraps in narrow tables. It used to be any attribute whose *name* ended
  in `_id`, which mangled ordinary business columns like `external_id`
  or `stripe_customer_id` into unreadable 8-character stumps (friction
  log P05). Callers with no resource in hand (the dashboard's metric
  tiles) pass nothing and get no truncation.
  """
  @spec cell(atom(), term(), [atom()]) :: String.t()
  def cell(key, value, foreign_keys \\ [])

  def cell(:id, value, _foreign_keys) when is_binary(value), do: truncate_id(value)

  def cell(key, value, foreign_keys) when is_atom(key) and is_binary(value) do
    if key in foreign_keys, do: truncate_id(value), else: to_string(value)
  end

  def cell(_key, %DateTime{} = value, _foreign_keys), do: short_datetime(value)
  def cell(_key, %NaiveDateTime{} = value, _foreign_keys), do: short_datetime(value)
  def cell(_key, nil, _foreign_keys), do: "—"
  def cell(_key, value, _foreign_keys) when is_atom(value), do: Atom.to_string(value)
  def cell(_key, value, _foreign_keys), do: to_string(value)

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
