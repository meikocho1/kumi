defmodule KumiStorage.ValidationTest do
  use ExUnit.Case, async: true

  alias KumiStorage.Validation

  describe "content-type allowlist" do
    test "accepts a default-allowed image type" do
      assert :ok = Validation.validate("a.jpg", "image/jpeg", 1_000)
    end

    test "rejects a type outside the allowlist" do
      assert {:error, :disallowed_content_type} =
               Validation.validate("a.exe", "application/x-msdownload", 1_000)
    end

    test "allowlist is overridable via opts" do
      assert {:error, :disallowed_content_type} =
               Validation.validate("a.pdf", "application/pdf", 1_000)

      assert :ok =
               Validation.validate("a.pdf", "application/pdf", 1_000,
                 allowed_content_types: ~w(application/pdf)
               )
    end
  end

  describe "size cap" do
    test "accepts a file under the default cap" do
      assert :ok = Validation.validate("a.jpg", "image/jpeg", 1_000)
    end

    test "rejects a file over the default cap" do
      assert {:error, :too_large} = Validation.validate("a.jpg", "image/jpeg", 100 * 1024 * 1024)
    end

    test "cap is overridable via opts" do
      assert {:error, :too_large} =
               Validation.validate("a.jpg", "image/jpeg", 500, max_bytes: 100)

      assert :ok = Validation.validate("a.jpg", "image/jpeg", 50, max_bytes: 100)
    end
  end

  test "size is checked before content type when both fail" do
    assert {:error, :too_large} =
             Validation.validate("a.exe", "application/x-msdownload", 100 * 1024 * 1024)
  end
end
