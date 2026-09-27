defmodule KumiStorage.Test.MnesiaAttachment do
  @moduledoc """
  `KumiStorage.Test.Attachment` on `Ash.DataLayer.Mnesia`, which transacts
  (Ets doesn't), under `KumiStorage.Test.FilterAuthorizer`: the path a
  host's filter-check policy takes, where Ash authorizes the create
  against the inserted row and rolls it back if that fails. Its `:upload`
  action is the generated one verbatim (the installer test checks that).
  The test creates the Mnesia table.
  """

  use Ash.Resource,
    domain: KumiStorage.Test.Domain,
    data_layer: Ash.DataLayer.Mnesia,
    authorizers: [KumiStorage.Test.FilterAuthorizer]

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
      public? false
    end

    timestamps()
  end

  @doc "`{backend, backend_opts}` for the current test process."
  def __kumi_storage_config__ do
    Process.get(:kumi_storage_test_config) ||
      raise "put {backend, opts} under :kumi_storage_test_config in the test process first"
  end
end
