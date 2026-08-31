defmodule KumiAdmin.AttributesTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Attributes
  alias KumiAdmin.Test.Credential

  defp names(attributes), do: Enum.map(attributes, & &1.name)

  # Friction log P04: `sensitive? true` was declared and ignored — the value
  # rendered on the list and the detail page.
  test "visible/1 drops attributes Ash marks sensitive?" do
    visible = names(Attributes.visible(Credential))

    assert :label in visible
    assert :external_id in visible
    refute :api_secret in visible
  end

  test "foreign_keys/1 names the belongs_to source attribute, not every `_id` column" do
    assert Attributes.foreign_keys(Credential) == [:account_id]
  end

  test "belongs_to_by_source_attribute/1 keys the relationship by its foreign key" do
    assert %{account_id: %{name: :account}} =
             Attributes.belongs_to_by_source_attribute(Credential)
  end

  describe "every attribute list in the admin goes through visible/1" do
    test "columns exclude sensitive attributes" do
      refute :api_secret in KumiAdmin.Columns.for_resource(Credential)
    end

    test "search never filters on a sensitive attribute" do
      fields = KumiAdmin.Search.searchable_fields(Credential)

      assert :external_id in fields
      refute :api_secret in fields
    end

    test "forms never accept a sensitive attribute in either direction" do
      fields =
        Credential
        |> KumiAdmin.FormFields.for_action(:create)
        |> Enum.map(& &1.attribute.name)

      assert :label in fields
      refute :api_secret in fields
    end
  end
end
