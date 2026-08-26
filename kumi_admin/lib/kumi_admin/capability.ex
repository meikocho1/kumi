defmodule KumiAdmin.Capability do
  @moduledoc """
  Cheap per-record button visibility via `Ash.can?/3`: hides New/Edit/Delete
  when the action doesn't exist on the resource, or the actor can't perform
  it. This is the honest-detection half of write support — the other half
  is the submit-time forbidden flash (`ResourceFormLive`/`ResourceShowLive`)
  for whatever `Ash.can?` can't cheaply rule out in advance (e.g. runtime
  checks it can only answer `:maybe` to, which `can?/3` treats as `true`).
  """

  @spec can_create?(module(), term()) :: boolean()
  def can_create?(resource, actor) do
    case Ash.Resource.Info.primary_action(resource, :create) do
      nil -> false
      action -> safe_can?({resource, action.name}, actor)
    end
  end

  @spec can_update?(struct(), term()) :: boolean()
  def can_update?(%resource{} = record, actor) do
    case Ash.Resource.Info.primary_action(resource, :update) do
      nil -> false
      action -> safe_can?({record, action.name}, actor)
    end
  end

  @spec can_destroy?(struct(), term()) :: boolean()
  def can_destroy?(%resource{} = record, actor) do
    case Ash.Resource.Info.primary_action(resource, :destroy) do
      nil -> false
      action -> safe_can?({record, action.name}, actor)
    end
  end

  # `Ash.can?/3` is documented as raising on unexpected errors; when it
  # can't cheaply answer, default to showing the button and let the
  # submit-time flash be the honest source of truth instead.
  defp safe_can?(subject, actor) do
    Ash.can?(subject, actor)
  rescue
    _ -> true
  end
end
