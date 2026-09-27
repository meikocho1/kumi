defmodule KumiAdmin.ResourceFormLiveTest do
  @moduledoc """
  Unit tests for the pure/injectable pieces of the create/edit form that
  don't need a LiveView mount: `belongs_to_options/3` (M5) and
  `field_input/1` (M5's blank-option omission), the nil-assign event
  guard (L5), and the upload path on either side of the upload channel —
  `upload_attachment/4` against the fixture Attachment's real `:upload`
  action, and `submit/3` with the Attachments it stored. All fixture
  resources are ETS-backed, so no database is needed.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KumiAdmin.{FormFields, ResourceFormLive}
  alias KumiAdmin.Test.{Account, Attachment, Contact, Credential, Person, StrictContact}

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource KumiAdmin.ResourceFormLiveTest.LockedAttachment
      resource KumiAdmin.ResourceFormLiveTest.LockedPerson
      resource KumiAdmin.ResourceFormLiveTest.Refusing
    end
  end

  # An Attachment whose `:upload` no actor may run.
  defmodule LockedAttachment do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

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
        argument :byte_size, :integer, allow_nil?: false
      end
    end

    attributes do
      uuid_primary_key :id
    end

    policies do
      policy always() do
        forbid_if always()
      end
    end
  end

  # A parent with an upload field that no actor may create.
  defmodule LockedPerson do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, create: :*]
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    relationships do
      belongs_to :avatar, KumiAdmin.Test.Attachment, public?: true
    end

    policies do
      policy always() do
        forbid_if always()
      end
    end
  end

  # A create that a change refuses with no field to attach the error to —
  # the case the old heuristic called "forbidden". Named "whole form", it
  # refuses with `fields: []`, which AshPhoenix files under `:_form`: a
  # form error, but still not one the page renders under a field.
  defmodule Refusing do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:name]

        change fn changeset, _context ->
          case Ash.Changeset.get_attribute(changeset, :name) do
            "whole form" ->
              Ash.Changeset.add_error(
                changeset,
                Ash.Error.Changes.InvalidChanges.exception(fields: [], message: "refused")
              )

            _name ->
              Ash.Changeset.add_error(changeset, "refused")
          end
        end
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end
  end

  defp create!(resource, attrs) do
    {:ok, record} = resource |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    record
  end

  defp temp_file!(contents) do
    path = Path.join(System.tmp_dir!(), "kumi_admin_upload_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp entry(overrides \\ %{}) do
    struct!(
      Phoenix.LiveView.UploadEntry,
      Map.merge(%{client_name: "avatar.png", client_type: "image/png", client_size: 1}, overrides)
    )
  end

  defp form_socket(resource) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        fields: FormFields.for_action(resource, :create),
        form: resource |> AshPhoenix.Form.for_create(:create) |> to_form(),
        actor: nil,
        text: KumiAdmin.Text.new(KumiAdmin.Test.App),
        resource: resource,
        mode: :new,
        mount_path: "/admin"
      }
    }
  end

  defp error_flash(socket), do: Phoenix.Flash.get(socket.assigns.flash, :error)

  defp attachment_ids, do: Attachment |> Ash.read!() |> Enum.map(& &1.id)

  describe "belongs_to_options/3 (M5)" do
    test "options are sorted, so the 100-row window is deterministic" do
      accounts = for n <- 1..3, do: create!(Account, %{name: "Account #{n}"})
      fields = FormFields.for_action(Contact, :create)

      options = ResourceFormLive.belongs_to_options(fields, nil, nil)[:account_id]
      ids = Enum.map(options, &elem(&1, 1))

      assert ids == Enum.sort(Enum.map(accounts, & &1.id))
    end

    test "the record's current foreign key survives even when it falls outside the 100-row window" do
      accounts = for _ <- 1..101, do: create!(Account, %{name: "Account"})
      outside_window_id = accounts |> Enum.map(& &1.id) |> Enum.max()
      contact = create!(Contact, %{name: "Ada", account_id: outside_window_id})

      fields = FormFields.for_action(Contact, :create)
      options = ResourceFormLive.belongs_to_options(fields, nil, contact)[:account_id]
      ids = Enum.map(options, &elem(&1, 1))

      # 100 from the window (the lowest 100 ids), the window fills only
      # to 100 by construction, plus the ensured current value.
      assert outside_window_id in ids
      assert length(ids) == 101
    end
  end

  describe "field_input/1 blank option omission (M5)" do
    test "a non-nullable belongs_to omits the blank <option> so it can never be blanked" do
      fields = FormFields.for_action(StrictContact, :create)
      account_field = Enum.find(fields, &(&1.attribute.name == :account_id))
      form = StrictContact |> AshPhoenix.Form.for_create(:create) |> to_form()

      html =
        render_component(&ResourceFormLive.field_input/1, %{
          field: form[:account_id],
          widget: account_field.widget,
          attribute: account_field.attribute,
          options: [],
          upload: nil,
          current_url: nil,
          text: KumiAdmin.Text.new(KumiAdmin.Test.App)
        })

      refute html =~ ~s(<option value="")
    end

    test "a nullable belongs_to keeps the blank <option>" do
      fields = FormFields.for_action(Contact, :create)
      account_field = Enum.find(fields, &(&1.attribute.name == :account_id))
      form = Contact |> AshPhoenix.Form.for_create(:create) |> to_form()

      html =
        render_component(&ResourceFormLive.field_input/1, %{
          field: form[:account_id],
          widget: account_field.widget,
          attribute: account_field.attribute,
          options: [],
          upload: nil,
          current_url: nil,
          text: KumiAdmin.Text.new(KumiAdmin.Test.App)
        })

      assert html =~ ~s(<option value="")
    end
  end

  describe "handle_event(\"save\", ...) guard against a nil form (L5)" do
    test "flashes the permission message instead of crashing when form is nil" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          form: nil,
          text: KumiAdmin.Text.new(KumiAdmin.Test.App)
        }
      }

      {:noreply, socket} = ResourceFormLive.handle_event("save", %{"form" => %{}}, socket)

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You don't have permission to do that."
    end
  end

  describe "upload_attachment/4 — the admin's side of the :upload contract" do
    test "calls :upload with the four arguments, and byte_size is the file's measured size" do
      path = temp_file!("12345")

      assert {:ok, attachment} =
               ResourceFormLive.upload_attachment(Attachment, path, entry(), nil)

      assert attachment.filename == "avatar.png"
      assert attachment.content_type == "image/png"
      assert attachment.storage_key == Path.basename(path)
      # The entry claims 1 byte; the browser's number is not what gets
      # validated or recorded.
      assert attachment.byte_size == 5
    end

    test "a file over the action's cap is rejected even when the client under-declares it" do
      path = temp_file!(:binary.copy("x", 2_000))

      assert {:error, :upload_too_large} =
               ResourceFormLive.upload_attachment(Attachment, path, entry(%{client_size: 1}), nil)

      assert attachment_ids() == []
    end

    test "a content-type rejection is upload_not_accepted, not forbidden" do
      path = temp_file!("<html>")

      assert {:error, :upload_not_accepted} =
               ResourceFormLive.upload_attachment(
                 Attachment,
                 path,
                 entry(%{client_type: "text/html"}),
                 nil
               )
    end

    test "any other refusal by the action is upload_rejected, not forbidden" do
      path = temp_file!("png")

      assert {:error, :upload_rejected} =
               ResourceFormLive.upload_attachment(
                 Attachment,
                 path,
                 entry(%{client_name: "backend-fails.png"}),
                 nil
               )
    end

    test "only a policy denial is forbidden" do
      path = temp_file!("png")

      assert {:error, :forbidden} =
               ResourceFormLive.upload_attachment(LockedAttachment, path, entry(), nil)
    end
  end

  describe "submit/3 — the save after the uploads were stored" do
    setup do
      {:ok, attachment} =
        ResourceFormLive.upload_attachment(Attachment, temp_file!("png"), entry(), nil)

      %{attachment: attachment}
    end

    test "an invalid submit destroys the Attachment it stored", %{attachment: attachment} do
      {:noreply, socket} =
        ResourceFormLive.submit(
          form_socket(Person),
          %{"name" => "", "avatar_id" => attachment.id},
          [attachment]
        )

      assert error_flash(socket) == "Please fix the errors below."
      refute attachment.id in attachment_ids()
    end

    test "a policy-forbidden submit says so, and leaves no Attachment behind", %{
      attachment: attachment
    } do
      {:noreply, socket} =
        ResourceFormLive.submit(
          form_socket(LockedPerson),
          %{"name" => "Ada", "avatar_id" => attachment.id},
          [attachment]
        )

      assert error_flash(socket) == "You don't have permission to do that."
      refute attachment.id in attachment_ids()
    end

    test "a successful submit keeps the Attachment and links it", %{attachment: attachment} do
      {:noreply, _socket} =
        ResourceFormLive.submit(
          form_socket(Person),
          %{"name" => "Ada", "avatar_id" => attachment.id},
          [attachment]
        )

      assert [%{avatar_id: avatar_id}] = Ash.read!(Person)
      assert avatar_id == attachment.id
      assert attachment.id in attachment_ids()
    end

    test "a refusal with no field to attach to is neither forbidden (M3) nor 'fix the errors'" do
      {:noreply, socket} = ResourceFormLive.submit(form_socket(Refusing), %{"name" => "x"}, [])

      assert error_flash(socket) == "Couldn't save this record."
    end

    test "an error on no rendered field is not 'fix the errors below' either" do
      {:noreply, socket} =
        ResourceFormLive.submit(form_socket(Refusing), %{"name" => "whole form"}, [])

      assert Keyword.has_key?(socket.assigns.form.errors, :_form)
      assert error_flash(socket) == "Couldn't save this record."
    end
  end

  describe "inbound params are narrowed to the rendered fields" do
    # LiveView events are client-controlled: `create: :*` accepts
    # `api_secret`, so anything that reached the action would be written.
    test "save drops a sensitive attribute the page never rendered" do
      {:noreply, _socket} =
        ResourceFormLive.handle_event(
          "save",
          %{"form" => %{"label" => "a", "api_secret" => "b"}},
          form_socket(Credential)
        )

      assert [credential] = Ash.read!(Credential)
      assert credential.label == "a"
      assert credential.api_secret == nil
    end

    test "save drops an upload field's foreign key posted without a picked file" do
      {:ok, existing} =
        ResourceFormLive.upload_attachment(Attachment, temp_file!("png"), entry(), nil)

      socket = ResourceFormLive.allow_uploads(form_socket(Person))

      {:noreply, _socket} =
        ResourceFormLive.handle_event(
          "save",
          %{"form" => %{"name" => "Ada", "avatar_id" => existing.id}},
          socket
        )

      assert [%{name: "Ada", avatar_id: nil}] = Ash.read!(Person)
    end

    test "validate keeps the rendered fields and their _unused_ markers, nothing else" do
      params = %{
        "label" => "a",
        "_unused_label" => "",
        "api_secret" => "b",
        "_unused_api_secret" => ""
      }

      {:noreply, socket} =
        ResourceFormLive.handle_event("validate", %{"form" => params}, form_socket(Credential))

      assert socket.assigns.form.params["label"] == "a"
      assert Map.has_key?(socket.assigns.form.params, "_unused_label")
      refute Map.has_key?(socket.assigns.form.params, "api_secret")
      refute Map.has_key?(socket.assigns.form.params, "_unused_api_secret")
    end
  end

  describe "allow_uploads/1" do
    test "caps the widget at kumi_storage's default max_bytes, not LiveView's 8 MB" do
      socket = ResourceFormLive.allow_uploads(form_socket(Person))

      assert socket.assigns.uploads.avatar.max_file_size == 10 * 1024 * 1024
      assert socket.assigns.uploads.avatar.max_entries == 1
    end
  end
end
