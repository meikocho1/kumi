defmodule KumiStorage.Test.FlakyBackend do
  @moduledoc """
  `KumiStorage.Backend.Local`, except that `fail_store: reason` or
  `fail_delete: reason` in opts makes that call return `{:error, reason}`.
  """

  @behaviour KumiStorage.Backend

  alias KumiStorage.Backend.Local

  @impl true
  def store(source, filename, content_type, opts) do
    case Keyword.fetch(opts, :fail_store) do
      {:ok, reason} -> {:error, reason}
      :error -> Local.store(source, filename, content_type, opts)
    end
  end

  @impl true
  def delete(key, opts) do
    case Keyword.fetch(opts, :fail_delete) do
      {:ok, reason} -> {:error, reason}
      :error -> Local.delete(key, opts)
    end
  end

  @impl true
  defdelegate path(key, opts), to: Local

  @impl true
  defdelegate open(key, opts), to: Local
end
