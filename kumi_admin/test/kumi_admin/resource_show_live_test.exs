defmodule KumiAdmin.ResourceShowLiveTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.ResourceShowLive

  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource KumiAdmin.ResourceShowLiveTest.Undeletable
      resource KumiAdmin.ResourceShowLiveTest.Referenced
    end
  end

  # Readable and creatable, never destroyable.
  defmodule Undeletable do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      defaults [:read, :destroy, create: :*]
    end

    attributes do
      uuid_primary_key :id
    end

    policies do
      policy action_type(:destroy) do
        forbid_if always()
      end

      policy action_type([:read, :create]) do
        authorize_if always()
      end
    end
  end

  # ETS has no foreign keys, so this destroy refuses the way AshPostgres
  # reports a row that children still reference: an `Ash.Error.Invalid`
  # carrying "would leave records behind" on the key.
  defmodule Referenced do
    @moduledoc false
    use Ash.Resource, domain: Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read, create: :*]

      destroy :destroy do
        primary? true
        require_atomic? false

        change fn changeset, _context ->
          Ash.Changeset.add_error(changeset, field: :id, message: "would leave records behind")
        end
      end
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defp delete_socket(record) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        record: record,
        actor: %{id: "someone"},
        resource: record.__struct__,
        mount_path: "/admin",
        text: KumiAdmin.Text.new(KumiAdmin.Test.App)
      }
    }
  end

  setup do
    relationship = Ash.Resource.Info.relationship(KumiAdmin.Test.Account, :contacts)
    %{relationship: relationship}
  end

  test "an :ok load result yields rows, columns, and no overflow when under the cap", %{
    relationship: relationship
  } do
    {:ok, contact} =
      KumiAdmin.Test.Contact
      |> Ash.Changeset.for_create(:create, %{name: "Ada"})
      |> Ash.create()

    loaded = %{contacts: [contact]}

    section =
      ResourceShowLive.build_has_many_section(
        relationship,
        [KumiAdmin.Test.Contact],
        10,
        {:ok, loaded}
      )

    assert section.destination == KumiAdmin.Test.Contact
    assert section.rows == [contact]
    assert section.has_more? == false
    assert section.error == nil
    assert section.linkable? == true
    assert :id in section.columns
  end

  test "an extra row past related_limit flips has_more? without changing displayed rows", %{
    relationship: relationship
  } do
    contacts =
      for n <- 1..3 do
        {:ok, contact} =
          KumiAdmin.Test.Contact
          |> Ash.Changeset.for_create(:create, %{name: "Contact #{n}"})
          |> Ash.create()

        contact
      end

    section =
      ResourceShowLive.build_has_many_section(
        relationship,
        [KumiAdmin.Test.Contact],
        2,
        {:ok, %{contacts: contacts}}
      )

    assert length(section.rows) == 2
    assert section.has_more? == true
  end

  test "an :error load result (policy-forbidden child) renders as an honest empty section, not a crash",
       %{relationship: relationship} do
    section =
      ResourceShowLive.build_has_many_section(
        relationship,
        [KumiAdmin.Test.Contact],
        10,
        {:error, %Ash.Error.Forbidden{}}
      )

    assert section.error == :forbidden
    assert section.rows == []
    assert section.has_more? == false
  end

  test "linkable? is false when the destination isn't in the app's declared resources", %{
    relationship: relationship
  } do
    section =
      ResourceShowLive.build_has_many_section(relationship, [], 10, {:ok, %{contacts: []}})

    assert section.linkable? == false
  end

  test "a non-Forbidden error is not swallowed into the forbidden state — it raises instead (M3)",
       %{relationship: relationship} do
    # Before this fix, ANY error (a DB outage, an invalid query, a cast
    # failure) was reported to the user as "No access" — indistinguishable
    # from a genuine policy denial. Only `Ash.Error.Forbidden` may map to
    # the forbidden state; anything else is a bug and must surface loudly.
    assert_raise Ash.Error.Invalid, fn ->
      ResourceShowLive.build_has_many_section(
        relationship,
        [KumiAdmin.Test.Contact],
        10,
        {:error, %Ash.Error.Invalid{}}
      )
    end
  end

  describe "handle_event(\"delete\", ...) guard against a nil record (L5)" do
    test "flashes the permission message instead of crashing when record is nil" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          record: nil,
          text: KumiAdmin.Text.new(KumiAdmin.Test.App)
        }
      }

      {:noreply, socket} = ResourceShowLive.handle_event("delete", %{}, socket)

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You don't have permission to do that."
    end
  end

  describe "handle_event(\"delete\", ...) failures (M3)" do
    test "a policy-forbidden destroy flashes the permission message" do
      record = Ash.create!(Undeletable, %{})

      {:noreply, socket} = ResourceShowLive.handle_event("delete", %{}, delete_socket(record))

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You don't have permission to do that."
    end

    test "a destroy refused for any other reason (a foreign key) is not reported as forbidden" do
      record = Ash.create!(Referenced, %{})

      {:noreply, socket} = ResourceShowLive.handle_event("delete", %{}, delete_socket(record))

      assert Phoenix.Flash.get(socket.assigns.flash, :error) == "Couldn't delete this record."
      assert [_still_there] = Ash.read!(Referenced)
    end
  end
end
