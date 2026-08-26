defmodule KumiAdmin.FormFieldsTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.FormFields
  alias KumiAdmin.Test.{Contact, Widget}

  describe "for_action/2 — field derivation" do
    test "only fields in the create action's accept list are returned, in declaration order" do
      fields = FormFields.for_action(Widget, :create)
      names = Enum.map(fields, & &1.attribute.name)

      # :hidden is not public? so it can never be accepted; everything else
      # is public and `create: :*` accepts every public+writable attribute.
      refute :hidden in names
      assert :a in names
      assert :status in names
      assert Enum.find_index(names, &(&1 == :a)) < Enum.find_index(names, &(&1 == :f))
    end

    test "update action derives the same public fields as create for these fixtures" do
      create_names = Widget |> FormFields.for_action(:create) |> Enum.map(& &1.attribute.name)
      update_names = Widget |> FormFields.for_action(:update) |> Enum.map(& &1.attribute.name)

      assert create_names == update_names
    end

    test "a belongs_to's generated foreign key is tagged :belongs_to, not its raw uuid type" do
      fields = FormFields.for_action(Contact, :create)
      account_field = Enum.find(fields, &(&1.attribute.name == :account_id))

      assert {:belongs_to, relationship} = account_field.widget
      assert relationship.destination == KumiAdmin.Test.Account
    end
  end

  describe "widget/2 — per-type widget selection" do
    test "boolean -> checkbox" do
      attribute = attribute(:active, Ash.Type.Boolean)
      assert FormFields.widget(attribute, nil) == :checkbox
    end

    test "integer -> number" do
      attribute = attribute(:count, Ash.Type.Integer)
      assert FormFields.widget(attribute, nil) == :number
    end

    test "decimal -> number" do
      attribute = attribute(:price, Ash.Type.Decimal)
      assert FormFields.widget(attribute, nil) == :number
    end

    test "date -> date" do
      attribute = attribute(:scheduled_on, Ash.Type.Date)
      assert FormFields.widget(attribute, nil) == :date
    end

    test "datetime -> datetime_local" do
      attribute = attribute(:sent_at, Ash.Type.UtcDatetime)
      assert FormFields.widget(attribute, nil) == :datetime_local
    end

    test "atom with one_of constraints -> select with the allowed values" do
      attribute = attribute(:stage, Ash.Type.Atom, one_of: [:lead, :won])
      assert FormFields.widget(attribute, nil) == {:select, [:lead, :won]}
    end

    test "atom without one_of constraints falls back to text" do
      attribute = attribute(:kind, Ash.Type.Atom, [])
      assert FormFields.widget(attribute, nil) == :text
    end

    test "plain short string -> text" do
      attribute = attribute(:name, Ash.Type.String)
      assert FormFields.widget(attribute, nil) == :text
    end

    test "unconstrained string named like long-form content -> textarea" do
      attribute = attribute(:description, Ash.Type.String)
      assert FormFields.widget(attribute, nil) == :textarea
    end

    test "string with a max_length constraint stays a text input even if long-form-named" do
      attribute = attribute(:body, Ash.Type.String, max_length: 100)
      assert FormFields.widget(attribute, nil) == :text
    end

    test "a belongs_to relationship always wins over the underlying uuid type" do
      attribute = attribute(:account_id, Ash.Type.UUID)
      relationship = %{destination: KumiAdmin.Test.Account}

      assert FormFields.widget(attribute, relationship) == {:belongs_to, relationship}
    end
  end

  defp attribute(name, type, constraints \\ []) do
    %{name: name, type: type, constraints: constraints}
  end
end
