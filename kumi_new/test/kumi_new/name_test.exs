defmodule KumiNew.NameTest do
  use ExUnit.Case, async: true

  alias KumiNew.Name

  @valid ["my_crm", "a", "app123", "my_crm_2"]
  @invalid ["MyCrm", "1app", "-my_app", "my-app", "my app", "", "my_App"]

  for name <- @valid do
    test "accepts valid name #{inspect(name)}" do
      assert Name.validate(unquote(name)) == :ok
    end
  end

  for name <- @invalid do
    test "rejects invalid name #{inspect(name)}" do
      assert {:error, message} = Name.validate(unquote(name))
      assert message =~ "lowercase"
    end
  end
end
