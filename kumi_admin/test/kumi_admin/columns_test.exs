defmodule KumiAdmin.ColumnsTest do
  use ExUnit.Case, async: true

  alias KumiAdmin.Columns

  test "for_resource/1 caps at the first 6 public attributes, in declared order" do
    assert Columns.for_resource(KumiAdmin.Test.Widget) == [:id, :a, :b, :c, :d, :e]
  end

  test "for_resource/1 excludes non-public attributes" do
    refute :hidden in Columns.for_resource(KumiAdmin.Test.Widget)
  end
end
