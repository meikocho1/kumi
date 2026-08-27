defmodule KumiStorage.Validation do
  @moduledoc """
  v1-mandatory validation at the storage boundary (blueprint §6 point 6):
  a size cap and a content-type allowlist. Call this BEFORE
  `KumiStorage.Backend.store/4` — the backend itself does not validate.
  """

  # Sensible image defaults, both overridable via opts.
  @default_max_bytes 10 * 1024 * 1024
  @default_allowed_content_types ~w(image/jpeg image/png image/gif image/webp)

  @type error :: {:error, :too_large | :disallowed_content_type}

  @doc """
  Validates a would-be upload. `opts` accepts `:max_bytes` and
  `:allowed_content_types` overrides.
  """
  @spec validate(String.t(), String.t(), non_neg_integer(), keyword()) :: :ok | error()
  def validate(_filename, content_type, byte_size, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    allowed_content_types =
      Keyword.get(opts, :allowed_content_types, @default_allowed_content_types)

    cond do
      byte_size > max_bytes -> {:error, :too_large}
      content_type not in allowed_content_types -> {:error, :disallowed_content_type}
      true -> :ok
    end
  end
end
