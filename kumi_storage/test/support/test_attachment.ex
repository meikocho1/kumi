defmodule KumiStorage.Test.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource KumiStorage.Test.Attachment
  end
end

defmodule KumiStorage.Test.Attachment do
  @moduledoc """
  The Attachment resource `mix kumi_storage.install` generates, on
  `Ash.DataLayer.Ets`: its `:upload` and `:destroy` actions are the
  generated ones verbatim (the installer test checks that), so the
  package's tests run the real trust boundary rather than matching the
  template's text.

  Test-only differences: `__kumi_storage_config__/0` reads the backend from
  the test process (so tests stay async, each with its own root),
  `KumiStorage.Test.BlockedActorAuthorizer` stands in for a host's
  policies, and `:upload_then_fail` fails after the store.
  """

  use Ash.Resource,
    domain: KumiStorage.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [KumiStorage.Test.BlockedActorAuthorizer]

  ets do
    private? true
  end

  actions do
    defaults [:read]

    create :upload do
      accept []

      argument :source, :term, allow_nil?: false
      argument :filename, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      argument :byte_size, :integer

      change fn changeset, _context ->
        {backend, backend_opts} = __MODULE__.__kumi_storage_config__()

        KumiStorage.Upload.prepare(changeset, backend, backend_opts)
      end
    end

    # `:upload`, plus an error raised inside the transaction — after the
    # store, as a failed INSERT would be.
    create :upload_then_fail do
      accept []

      argument :source, :term, allow_nil?: false
      argument :filename, :string, allow_nil?: false
      argument :content_type, :string, allow_nil?: false
      argument :byte_size, :integer

      change fn changeset, _context ->
        {backend, backend_opts} = __MODULE__.__kumi_storage_config__()

        KumiStorage.Upload.prepare(changeset, backend, backend_opts)
      end

      change before_action(fn changeset, _context ->
               Ash.Changeset.add_error(changeset, message: "failed after the store")
             end)
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change after_transaction(fn _changeset, result, _context ->
               {backend, backend_opts} = __MODULE__.__kumi_storage_config__()

               KumiStorage.Upload.delete_stored(result, backend, backend_opts)
             end)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :filename, :string do
      allow_nil? false
      public? true
    end

    attribute :content_type, :string do
      allow_nil? false
      public? true
    end

    attribute :byte_size, :integer do
      allow_nil? false
      public? true
    end

    attribute :storage_key, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  @doc "`{backend, backend_opts}` for the current test process."
  def __kumi_storage_config__ do
    Process.get(:kumi_storage_test_config) ||
      raise "put {backend, opts} under :kumi_storage_test_config in the test process first"
  end
end
