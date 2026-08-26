defmodule KumiNew.Name do
  @moduledoc """
  App name validation — same rule phx.new uses: lowercase snake_case,
  starting with a letter, safe as both an atom and a directory name.
  """

  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(name) when is_binary(name) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      :ok
    else
      {:error,
       "Application name must start with a lowercase letter and only contain " <>
         "lowercase letters, numbers, and underscores (e.g. my_crm), got: #{inspect(name)}"}
    end
  end
end
