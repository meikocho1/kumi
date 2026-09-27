defmodule KumiStorage.Upload do
  @moduledoc """
  The storage calls the generated Attachment resource makes: `prepare/3`
  from its `:upload` create action and `delete_stored/3` from its destroy
  action. They are plain functions called from plain Ash — the resource
  still shows where every storage call happens — so a fix here reaches
  existing hosts on a dependency upgrade instead of being frozen into each
  generated file.

  Like the backends, both take the backend and its opts explicitly and
  never read Application config.

  The size is measured from the source itself; a size the caller declares
  is never trusted. The content type is still the caller's claim: the
  backend derives the stored extension from it and `KumiStorage.Plug`
  serves with `nosniff`, so a mislabelled file is served as the allowed
  type it was labelled with, never as HTML.
  """

  require Logger

  alias KumiStorage.Validation

  @doc """
  The size of an upload source in bytes: `File.stat/1` for `{:path, path}`,
  `byte_size/1` for `{:binary, data}`. Any other shape is
  `{:error, :invalid_source}`.
  """
  @spec measure(term()) :: {:ok, non_neg_integer()} | {:error, :invalid_source | File.posix()}
  def measure({:path, path}) when is_binary(path) do
    with {:ok, %File.Stat{size: size}} <- File.stat(path), do: {:ok, size}
  end

  def measure({:binary, data}) when is_binary(data), do: {:ok, byte_size(data)}
  def measure(_source), do: {:error, :invalid_source}

  @doc """
  The body of the `:upload` action's change.

  Reads the `:source`, `:filename` and `:content_type` arguments, measures
  the source and runs `KumiStorage.Validation.validate/4` on the measured
  size, then sets `filename`, `content_type` and `byte_size`. A declared
  `:byte_size` argument is ignored.

  Nothing is stored while the changeset is only being built (a form
  validate, `Ash.can?/3`). `backend.store/4` runs in a `before_action`
  hook, which Ash runs after the up-front authorization, and sets
  `storage_key`. If the create fails after that, including a policy Ash
  can only check against the inserted row, an `after_transaction` hook
  deletes the stored file. A backend failure is logged and reported as a
  fixed "upload failed" error, so backend internals never reach the
  caller.
  """
  @spec prepare(Ash.Changeset.t(), module(), keyword()) :: Ash.Changeset.t()
  def prepare(changeset, backend, backend_opts) do
    source = Ash.Changeset.get_argument(changeset, :source)
    filename = Ash.Changeset.get_argument(changeset, :filename)
    content_type = Ash.Changeset.get_argument(changeset, :content_type)

    with {:ok, byte_size} <- measure(source),
         :ok <- Validation.validate(filename, content_type, byte_size, backend_opts) do
      ref = make_ref()

      changeset
      |> Ash.Changeset.force_change_attribute(:filename, filename)
      |> Ash.Changeset.force_change_attribute(:content_type, content_type)
      |> Ash.Changeset.force_change_attribute(:byte_size, byte_size)
      # before_action, not before_transaction: with a before_transaction
      # hook, Ash raises CannotFilterCreates for any policy it can only check
      # against the inserted row, such as `expr(owner_id == ^actor(:id))`.
      # The copy runs inside the transaction as a result.
      |> Ash.Changeset.before_action(fn changeset ->
        store(changeset, ref, source, filename, content_type, backend, backend_opts)
      end)
      # When the transaction fails, Ash hands after_transaction the
      # changeset from before it started, without the key. So the key goes
      # in the process dictionary under this ref: Ash runs both hooks in
      # the same process.
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        delete_on_error(ref, result, backend, backend_opts)
      end)
    else
      {:error, :invalid_source} ->
        Ash.Changeset.add_error(changeset,
          field: :source,
          message: "must be {:path, path} or {:binary, data}"
        )

      {:error, :too_large} ->
        Ash.Changeset.add_error(changeset, field: :byte_size, message: "is too large")

      {:error, :disallowed_content_type} ->
        Ash.Changeset.add_error(changeset,
          field: :content_type,
          message: "is not an allowed content type"
        )

      {:error, reason} ->
        upload_failed(changeset, reason)
    end
  end

  @doc """
  The body of the destroy action's `after_transaction` change.

  Once a destroy has committed (`{:ok, record}`), deletes the record's
  stored file. The row is already gone, so a backend failure is logged
  with the key, for an operator to clean up, rather than returned. The
  result is returned unchanged; any other result passes straight through.
  """
  @spec delete_stored(result, module(), keyword()) :: result when result: term()
  def delete_stored({:ok, record} = result, backend, backend_opts) do
    delete(record.storage_key, backend, backend_opts)
    result
  end

  def delete_stored(result, _backend, _backend_opts), do: result

  defp store(changeset, ref, source, filename, content_type, backend, backend_opts) do
    case backend.store(source, filename, content_type, backend_opts) do
      {:ok, key} ->
        Process.put({__MODULE__, ref}, key)
        Ash.Changeset.force_change_attribute(changeset, :storage_key, key)

      {:error, reason} ->
        upload_failed(changeset, reason)
    end
  end

  defp delete_on_error(ref, result, backend, backend_opts) do
    case {Process.delete({__MODULE__, ref}), result} do
      {nil, _result} -> :ok
      {key, {:error, _}} -> delete(key, backend, backend_opts)
      {_key, _ok} -> :ok
    end

    result
  end

  defp delete(key, backend, backend_opts) do
    case backend.delete(key, backend_opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("kumi_storage: stored file #{key} was not deleted: #{inspect(reason)}")
    end
  end

  defp upload_failed(changeset, reason) do
    Logger.warning("kumi_storage: upload failed: #{inspect(reason)}")
    Ash.Changeset.add_error(changeset, message: "upload failed")
  end
end
