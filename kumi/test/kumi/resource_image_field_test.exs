defmodule Kumi.ResourceImageFieldTest do
  # `:image` is sugar for `belongs_to` (blueprint §6 point 1): a
  # `field :name, :image, to: Target` parses into the exact same
  # `FieldSpec` a hand-written `belongs_to :name, Target` would, so
  # `Kumi.Resource.Codegen` never has to special-case it — the expand ==
  # compiled invariant holds for free, without any Codegen changes. This
  # suite covers the FieldSpec parse layer (pure, no DB) plus one full
  # macro-compile smoke test.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Kumi.Resource.FieldSpec
  alias Kumi.Test.Resource.Account

  describe "parse/2 — :image is sugar for belongs_to" do
    test "produces the identical FieldSpec a hand-written belongs_to would" do
      image_ast =
        quote do
          field :avatar, :image, to: Kumi.Test.Resource.Account
        end

      belongs_to_ast =
        quote do
          belongs_to :avatar, Kumi.Test.Resource.Account
        end

      assert FieldSpec.parse(image_ast, __ENV__) == FieldSpec.parse(belongs_to_ast, __ENV__)

      assert [%FieldSpec{kind: :belongs_to, name: :avatar, type: Account, opts: []}] =
               FieldSpec.parse(image_ast, __ENV__)
    end

    test "missing `to:` raises a helpful compile-time error (no opts)" do
      ast = quote(do: field(:avatar, :image))

      assert_raise ArgumentError, ~r/requires a `to:` target/, fn ->
        FieldSpec.parse(ast, __ENV__)
      end
    end

    test "missing `to:` raises a helpful compile-time error (empty opts)" do
      ast = quote(do: field(:avatar, :image, []))

      assert_raise ArgumentError, ~r/requires a `to:` target/, fn ->
        FieldSpec.parse(ast, __ENV__)
      end
    end

    test "`to:` naming a nonexistent module raises a helpful compile-time error" do
      ast = quote(do: field(:avatar, :image, to: Kumi.Test.NoSuchModule))

      assert_raise ArgumentError, ~r/does not exist or is not an Ash resource/, fn ->
        FieldSpec.parse(ast, __ENV__)
      end
    end

    test "`to:` naming a module that isn't an Ash resource raises a helpful compile-time error" do
      ast = quote(do: field(:avatar, :image, to: Kumi.Resource.Codegen))

      assert_raise ArgumentError, ~r/does not exist or is not an Ash resource/, fn ->
        FieldSpec.parse(ast, __ENV__)
      end
    end
  end

  describe "end-to-end: use Kumi.Resource with an :image field" do
    test "compiles to a plain belongs_to — expand output matches, no :image leaks into source" do
      source = """
      defmodule Kumi.Test.Resource.ImageFieldCheck do
        use Kumi.Resource,
          domain: Kumi.Test.ResourceDomain,
          repo: Kumi.Test.Repo,
          table: "kumi_test_resource_image_field_check"

        fields do
          field :name, :string, required: true
          field :avatar, :image, to: Kumi.Test.Resource.Account
        end
      end
      """

      # Not registered in ResourceDomain's `resources do ... end` — Ash
      # only warns (doesn't raise) about that, same as the pre-existing
      # expand-invariant test in resource_test.exs; captured so this
      # test's own output stays clean.
      capture_io(:stderr, fn -> Code.compile_string(source) end)

      mod = Kumi.Test.Resource.ImageFieldCheck

      rel = Ash.Resource.Info.relationship(mod, :avatar)
      assert rel.type == :belongs_to
      assert rel.destination == Account

      expanded = mod.__kumi_expand__()
      assert expanded =~ "belongs_to :avatar, Kumi.Test.Resource.Account"
      refute expanded =~ ":image"
    end
  end
end
