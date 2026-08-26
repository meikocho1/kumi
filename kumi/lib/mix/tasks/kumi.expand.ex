defmodule Mix.Tasks.Kumi.Expand do
  @moduledoc """
  Prints the Ash resource source a `Kumi.Resource` shorthand module
  compiles to — the "Show Ash" expansion (blueprint §0 D1). This is not a
  re-derivation: it prints exactly the string `Kumi.Resource` itself
  compiled from (`Kumi.Resource.Codegen.generate/3`), so it can never
  drift from what actually runs.

      mix kumi.expand MyApp.Customer
  """
  @shortdoc "Show the Ash resource a Kumi.Resource shorthand expands to"

  use Mix.Task

  @impl Mix.Task
  def run([module_name]) do
    Mix.Task.run("compile")

    module = Module.concat([module_name])

    cond do
      not Code.ensure_loaded?(module) ->
        Mix.raise("mix kumi.expand: module #{module_name} not found (typo, or not compiled?)")

      function_exported?(module, :__kumi_expand__, 0) ->
        Mix.shell().info(module.__kumi_expand__())

      Ash.Resource.Info.resource?(module) ->
        Mix.raise(
          "mix kumi.expand: #{module_name} is already a plain Ash resource — nothing to expand"
        )

      true ->
        Mix.raise("mix kumi.expand: #{module_name} is not a Kumi.Resource shorthand module")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix kumi.expand MyApp.SomeResource")
  end
end
