defmodule KumiAdmin.ResourceFormLiveTest do
  @moduledoc """
  Unit tests for the pure/injectable pieces of the create/edit form that
  don't need a LiveView mount: `belongs_to_options/3` (M5) and
  `field_input/1` (M5's blank-option omission), plus the nil-assign event
  guard (L5). All fixture resources are ETS-backed, so no database is
  needed.
  """

  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias KumiAdmin.{FormFields, ResourceFormLive}
  alias KumiAdmin.Test.{Account, Contact, StrictContact}

  defp create!(resource, attrs) do
    {:ok, record} = resource |> Ash.Changeset.for_create(:create, attrs) |> Ash.create()
    record
  end

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
          current_url: nil
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
          current_url: nil
        })

      assert html =~ ~s(<option value="")
    end
  end

  describe "handle_event(\"save\", ...) guard against a nil form (L5)" do
    test "flashes the permission message instead of crashing when form is nil" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, form: nil}
      }

      {:noreply, socket} = ResourceFormLive.handle_event("save", %{"form" => %{}}, socket)

      assert Phoenix.Flash.get(socket.assigns.flash, :error) ==
               "You don't have permission to do that."
    end
  end
end
