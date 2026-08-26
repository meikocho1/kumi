defmodule KumiAdmin.ResourceFormLive do
  @moduledoc """
  Generic create/edit form, built on `AshPhoenix.Form` (validate-on-change,
  submit via the resource's primary create/update action). Fields come from
  `KumiAdmin.FormFields.for_action/2` — the intersection of the action's
  `accept` list and public attributes, each tagged with an input widget.

  Mounted twice by `KumiAdmin.Router`: without `:id` for `.../new`, with
  `:id` for `.../:id/edit`. Policy-forbidden submits (and any submit error
  with no field to attach to) render a flash instead of crashing — same
  honesty stance as the read-only LiveViews.
  """

  use Phoenix.LiveView

  alias KumiAdmin.Components.Shell

  def mount(params, session, socket) do
    context = KumiAdmin.Context.resolve(session, params, socket)

    socket =
      socket
      |> assign(app: context.app, mount_path: context.mount_path)
      |> assign(actor: context.actor, resource: context.resource)
      |> load_form(params["id"])

    {:ok, socket}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, record} ->
        slug = KumiAdmin.Slug.for_resource(socket.assigns.resource)
        verb = if socket.assigns.mode == :new, do: "created", else: "updated"

        {:noreply,
         socket
         |> put_flash(:info, "#{Phoenix.Naming.humanize(slug)} #{verb}.")
         |> push_navigate(to: "#{socket.assigns.mount_path}/#{slug}/#{record.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, submit_error_message(form))
         |> assign(form: form)}
    end
  end

  # A submit failure with no field-attributable errors is, in practice, a
  # policy-forbidden action rather than bad input — AshPhoenix.Form only
  # attaches errors to fields it recognizes from the changeset/query.
  defp submit_error_message(form) do
    case AshPhoenix.Form.errors(form) do
      [] -> "You don't have permission to do that."
      _ -> "Please fix the errors below."
    end
  end

  defp load_form(socket, id) do
    case socket.assigns.resource do
      nil ->
        assign(socket, error: :not_found, mode: nil, fields: [], form: nil, belongs_to_options: %{})

      resource ->
        if id, do: edit_form(socket, resource, id), else: new_form(socket, resource)
    end
  end

  defp new_form(socket, resource) do
    actor = socket.assigns.actor
    action = Ash.Resource.Info.primary_action!(resource, :create).name
    fields = KumiAdmin.FormFields.for_action(resource, :create)
    form = AshPhoenix.Form.for_create(resource, action, actor: actor) |> to_form()

    assign(socket,
      error: nil,
      mode: :new,
      fields: fields,
      form: form,
      belongs_to_options: belongs_to_options(fields, actor)
    )
  end

  defp edit_form(socket, resource, id) do
    actor = socket.assigns.actor

    case Ash.get(resource, id, actor: actor) do
      {:ok, record} ->
        action = Ash.Resource.Info.primary_action!(resource, :update).name
        fields = KumiAdmin.FormFields.for_action(resource, :update)
        form = AshPhoenix.Form.for_update(record, action, actor: actor) |> to_form()

        assign(socket,
          error: nil,
          mode: :edit,
          fields: fields,
          form: form,
          belongs_to_options: belongs_to_options(fields, actor)
        )

      {:error, _reason} ->
        assign(socket,
          error: :forbidden,
          mode: nil,
          fields: [],
          form: nil,
          belongs_to_options: %{}
        )
    end
  end

  defp belongs_to_options(fields, actor) do
    fields
    |> Enum.filter(&match?({:belongs_to, _}, &1.widget))
    |> Map.new(fn %{attribute: attribute, widget: {:belongs_to, relationship}} ->
      {attribute.name, load_options(relationship.destination, actor)}
    end)
  end

  defp load_options(destination, actor) do
    case Ash.read(Ash.Query.limit(destination, 100), actor: actor) do
      {:ok, records} -> Enum.map(records, &{KumiAdmin.Format.record_label(&1), &1.id})
      {:error, _reason} -> []
    end
  end

  defp select?({:select, _}), do: true
  defp select?({:belongs_to, _}), do: true
  defp select?(_), do: false

  defp select_options({:select, values}, _options), do: Enum.map(values, &{Phoenix.Naming.humanize(&1), &1})
  defp select_options({:belongs_to, _relationship}, options), do: options

  defp truthy?(value), do: value in [true, "true", "on"]

  defp translate_error({msg, opts}) when is_list(opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error({msg, _opts}), do: msg
  defp translate_error(msg) when is_binary(msg), do: msg

  attr :field, Phoenix.HTML.FormField, required: true
  attr :widget, :any, required: true
  attr :options, :list, default: []

  defp field_input(assigns) do
    ~H"""
    <input
      :if={@widget == :text}
      type="text"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="kumi-admin-input"
    />
    <textarea
      :if={@widget == :textarea}
      id={@field.id}
      name={@field.name}
      class="kumi-admin-input"
    >{@field.value}</textarea>
    <input
      :if={@widget == :number}
      type="number"
      step="any"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="kumi-admin-input"
    />
    <input :if={@widget == :checkbox} type="hidden" name={@field.name} value="false" />
    <input
      :if={@widget == :checkbox}
      type="checkbox"
      id={@field.id}
      name={@field.name}
      value="true"
      checked={truthy?(@field.value)}
      class="kumi-admin-checkbox"
    />
    <input
      :if={@widget == :date}
      type="date"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="kumi-admin-input"
    />
    <input
      :if={@widget == :datetime_local}
      type="datetime-local"
      id={@field.id}
      name={@field.name}
      value={@field.value}
      class="kumi-admin-input"
    />
    <select :if={select?(@widget)} id={@field.id} name={@field.name} class="kumi-admin-input">
      <option value=""></option>
      <option
        :for={{label, value} <- select_options(@widget, @options)}
        value={value}
        selected={to_string(@field.value) == to_string(value)}
      >
        {label}
      </option>
    </select>
    """
  end

  def render(assigns) do
    ~H"""
    <Shell.shell app={@app} mount_path={@mount_path} active_resource={@resource} flash={@flash}>
      <a
        :if={@resource}
        href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@resource)}"}
        class="kumi-admin-back-link"
      >
        &larr; Back to {KumiAdmin.Label.plural(@resource)}
      </a>

      <p :if={@error == :not_found} class="kumi-admin-empty">
        Unknown resource.
      </p>

      <p :if={@error == :forbidden} class="kumi-admin-empty">
        No access or no record.
      </p>

      <.form :if={is_nil(@error)} for={@form} id="resource-form" phx-change="validate" phx-submit="save">
        <div :for={field <- @fields} class="kumi-admin-field">
          <label class="kumi-admin-field-label" for={@form[field.attribute.name].id}>
            {Phoenix.Naming.humanize(field.attribute.name)}
          </label>
          <.field_input
            field={@form[field.attribute.name]}
            widget={field.widget}
            options={Map.get(@belongs_to_options, field.attribute.name, [])}
          />
          <p :for={msg <- @form[field.attribute.name].errors} class="kumi-admin-field-error">
            {translate_error(msg)}
          </p>
        </div>
        <div class="kumi-admin-actions">
          <button type="submit" class="kumi-admin-button">Save</button>
        </div>
      </.form>
    </Shell.shell>
    """
  end
end
