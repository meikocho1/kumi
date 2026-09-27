defmodule KumiAdmin.ResourceFormLive do
  @moduledoc """
  Generic create/edit form, built on `AshPhoenix.Form` (validate-on-change,
  submit via the resource's primary create/update action). Fields come from
  `KumiAdmin.FormFields.for_action/2` — the intersection of the action's
  `accept` list and public attributes, each tagged with an input widget.

  Mounted twice by `KumiAdmin.Router`: without `:id` for `.../new`, with
  `:id` for `.../:id/edit`. A failed submit renders a flash instead of
  crashing — "no permission" only for a real policy denial, "fix the
  errors" otherwise — same honesty stance as the read-only LiveViews.

  Picked files are stored (through the Attachment's `:upload` action)
  before the submit, because the parent needs the new foreign key. When
  the submit then fails, the Attachments it stored are destroyed again,
  and the file has to be picked again.
  """

  use Phoenix.LiveView

  alias KumiAdmin.Components.Shell

  # Image-only for v1, matching KumiStorage.Validation's default content-type
  # allowlist. A single file: the widget replaces, it never appends.
  @upload_extensions ~w(.jpg .jpeg .png .gif .webp)

  def mount(params, session, socket) do
    context = KumiAdmin.Context.resolve(session, params, socket)

    case KumiAdmin.Gate.check(context, socket) do
      {:halt, socket} ->
        {:ok, socket}

      {:cont, socket} ->
        socket =
          socket
          |> assign(
            app: context.app,
            mount_path: context.mount_path,
            sign_out_path: context.sign_out_path,
            text: context.text
          )
          |> assign(actor: context.actor, resource: context.resource)
          |> load_form(params["id"])
          |> allow_uploads()

        {:ok, socket}
    end
  end

  def handle_event("validate", %{"form" => params}, socket) do
    params = permitted_params(params, socket.assigns.fields)
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  # LiveView events come from the client, not from the rendered DOM — an
  # authenticated user can push "save" over the socket while the page is
  # in its not-found/forbidden/no-action state (`form` is nil), even
  # though the Save button isn't rendered there. Guard it rather than let
  # `AshPhoenix.Form.submit(nil, ...)` crash the process (L5).
  def handle_event("save", _params, %{assigns: %{form: nil}} = socket) do
    {:noreply, put_flash(socket, :error, t(socket, :forbidden))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params = permitted_params(params, socket.assigns.fields)

    case apply_uploads(socket, params) do
      {:ok, params, created} -> submit(socket, params, created)
      {:error, key} -> {:noreply, put_flash(socket, :error, t(socket, key))}
    end
  end

  # Event params are whatever the client sends, not what the page
  # rendered: keep only the fields this form shows (plus LiveView's
  # `"_unused_" <> name` used-input markers for them). A `sensitive?` or
  # private attribute the action happens to accept, an argument the admin
  # never renders, and an upload field's foreign key — which only
  # `apply_uploads/2` may set, after the `:upload` action validated the
  # file — are all dropped here. The action's `accept` list and policies
  # remain the write boundary; this only stops the admin forwarding more
  # than it asked for.
  defp permitted_params(params, fields) do
    names =
      for %{attribute: attribute, widget: widget} <- fields,
          not match?({:upload, _}, widget),
          do: Atom.to_string(attribute.name)

    Map.filter(params, fn
      {"_unused_" <> name, _value} -> name in names
      {name, _value} -> name in names
    end)
  end

  # The half of "save" after the uploads were consumed, split out so it is
  # testable without a connected upload channel. `created` are the
  # Attachments this submit stored: when the submit fails nothing
  # references them, so they are discarded rather than left as orphans
  # (the user picks the file again either way — the entry is consumed).
  @doc false
  def submit(socket, params, created) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, record} ->
        slug = KumiAdmin.Slug.for_resource(socket.assigns.resource)
        key = if socket.assigns.mode == :new, do: :created, else: :updated

        # Whole-phrase templates, not "#{noun} #{verb}." — the noun's
        # position and the particle after it differ per language.
        flash =
          KumiAdmin.Text.string(socket.assigns.text, key,
            name: KumiAdmin.Text.resource(socket.assigns.text, socket.assigns.resource)
          )

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> push_navigate(to: "#{socket.assigns.mount_path}/#{slug}/#{record.id}")}

      {:error, form} ->
        discard_attachments(created, socket.assigns.actor)

        {:noreply,
         socket
         |> put_flash(:error, t(socket, submit_error_key(form)))
         |> assign(form: form)}
    end
  end

  # `:uploads` is a LiveView-reserved assign — it can only be set via
  # `allow_upload/3` (never plain `assign`/`assign_new`), so a resource
  # with no upload fields simply never gets the key at all. The template
  # reads it defensively (`Map.get(assigns, :uploads, %{})`) rather than
  # `@uploads`, which would raise for that case.
  #
  # `max_file_size` is KumiStorage.Validation's default `max_bytes`,
  # restated here because kumi_admin does not depend on kumi_storage —
  # LiveView's own default (8_000_000) would reject files storage
  # accepts. It is a ceiling: a host that lowers `max_bytes` is enforced
  # by the `:upload` action; one that raises it above this is not
  # reflected in the widget.
  @doc false
  def allow_uploads(socket) do
    socket.assigns.fields
    |> Enum.filter(&match?({:upload, _}, &1.widget))
    |> Enum.reduce(socket, fn %{widget: {:upload, relationship}}, socket ->
      allow_upload(socket, relationship.name,
        accept: @upload_extensions,
        max_entries: 1,
        max_file_size: 10 * 1024 * 1024
      )
    end)
  end

  # Consumes each upload field's selected file (if any), creating the
  # Attachment via its host-generated `:upload` action (blueprint §6 point
  # 8 — kumi_admin never touches storage directly) and merging the
  # resulting id into `params` as the belongs_to's FK. A field left
  # untouched (no new file picked) is simply absent from `params`, so an
  # existing attachment on edit is left as-is — replacing it is the only
  # way to change it, and the old attachment is then an intentional
  # orphan (blueprint §6 point 9's documented deferral). Returns the
  # Attachments it created so a failed submit can discard them; a failed
  # upload discards the ones stored before it.
  defp apply_uploads(socket, params) do
    socket.assigns.fields
    |> Enum.filter(&match?({:upload, _}, &1.widget))
    |> Enum.reduce_while({:ok, params, []}, fn %{
                                                 attribute: attribute,
                                                 widget: {:upload, relationship}
                                               },
                                               {:ok, params, created} ->
      case consume_upload(socket, relationship) do
        {:ok, nil} ->
          {:cont, {:ok, params, created}}

        {:ok, attachment} ->
          params = Map.put(params, Atom.to_string(attribute.name), attachment.id)
          {:cont, {:ok, params, [attachment | created]}}

        {:error, key} ->
          discard_attachments(created, socket.assigns.actor)
          {:halt, {:error, key}}
      end
    end)
  end

  defp consume_upload(socket, relationship) do
    actor = socket.assigns.actor

    result =
      consume_uploaded_entries(socket, relationship.name, fn %{path: path}, entry ->
        {:ok, upload_attachment(relationship.destination, path, entry, actor)}
      end)

    case result do
      [] -> {:ok, nil}
      [first | _] -> first
    end
  end

  # Stores one consumed upload entry through `destination`'s `:upload`
  # action — the admin's whole side of that contract, public so it is
  # testable against a real action. Runs inside the consume callback,
  # while the temp file at `path` exists, so `byte_size` is the file's
  # measured size, not the browser's `client_size`. `filename` and
  # `content_type` are still what the browser declared; the action is the
  # trust boundary for those.
  @doc false
  def upload_attachment(destination, path, entry, actor) do
    destination
    |> Ash.create(
      %{
        source: {:path, path},
        filename: entry.client_name,
        content_type: entry.client_type,
        byte_size: File.stat!(path).size
      },
      action: :upload,
      actor: actor
    )
    |> case do
      {:ok, attachment} -> {:ok, attachment}
      {:error, error} -> {:error, upload_error_key(error)}
    end
  end

  # Only a policy denial is "no permission" (M3). The `:upload` action
  # reports its own size and content-type rejections as field errors on
  # `:byte_size` / `:content_type`; anything else it refused is
  # `:upload_rejected`, not a permission problem.
  defp upload_error_key(%Ash.Error.Forbidden{}), do: :forbidden

  defp upload_error_key(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(errors, &match?(%{field: :byte_size}, &1)) -> :upload_too_large
      Enum.any?(errors, &match?(%{field: :content_type}, &1)) -> :upload_not_accepted
      true -> :upload_rejected
    end
  end

  defp upload_error_key(_error), do: :upload_rejected

  # Best-effort cleanup of Attachments nothing references. Destroy is not
  # part of the marker/`:upload`/URL contract, hence the guard; the
  # generated primary destroy also deletes the stored file. The result is
  # ignored — the failure the user needs to hear about is the submit's.
  defp discard_attachments(created, actor) do
    Enum.each(created, fn %resource{} = attachment ->
      if Ash.Resource.Info.primary_action(resource, :destroy) do
        Ash.destroy(attachment, actor: actor)
      end
    end)
  end

  # Only an actual policy denial is "no permission" (M3). Everything else —
  # a field error, a constraint the data layer reported, a change that
  # refused the input — is the form's to fix. The errors AshPhoenix keeps
  # are the ones inside the error class, so the check is on each one's
  # `class`, not on an `%Ash.Error.Forbidden{}` wrapper.
  defp submit_error_key(form) do
    forbidden? =
      form
      |> AshPhoenix.Form.raw_errors(for_path: :all)
      |> Map.values()
      |> List.flatten()
      |> Enum.any?(&match?(%{class: :forbidden}, &1))

    if forbidden?, do: :forbidden, else: :fix_errors
  end

  defp load_form(socket, id) do
    case socket.assigns.resource do
      nil ->
        assign(socket,
          error: :not_found,
          mode: nil,
          fields: [],
          form: nil,
          record: nil,
          belongs_to_options: %{}
        )

      resource ->
        if id, do: edit_form(socket, resource, id), else: new_form(socket, resource)
    end
  end

  # `Ash.Resource.Info.primary_action/2` (non-bang) — a resource with no
  # primary create/update action (e.g. `actions do defaults [:read] end`)
  # degrades to the `:no_action` state instead of letting the bang variant
  # raise and crash the route (M6). `Capability.can_create?/2` already
  # hides the New/Edit buttons for this case; this makes the route itself
  # honest when reached directly.
  defp new_form(socket, resource) do
    case Ash.Resource.Info.primary_action(resource, :create) do
      nil ->
        no_action_state(socket)

      action ->
        actor = socket.assigns.actor
        fields = KumiAdmin.FormFields.for_action(resource, :create)
        form = AshPhoenix.Form.for_create(resource, action.name, actor: actor) |> to_form()

        assign(socket,
          error: nil,
          mode: :new,
          fields: fields,
          form: form,
          record: nil,
          belongs_to_options: belongs_to_options(fields, actor, nil)
        )
    end
  end

  defp edit_form(socket, resource, id) do
    actor = socket.assigns.actor

    case Ash.get(resource, id, actor: actor) do
      {:ok, record} ->
        case Ash.Resource.Info.primary_action(resource, :update) do
          nil ->
            no_action_state(socket)

          action ->
            fields = KumiAdmin.FormFields.for_action(resource, :update)
            record = load_upload_relationships(record, fields, actor)
            form = AshPhoenix.Form.for_update(record, action.name, actor: actor) |> to_form()

            assign(socket,
              error: nil,
              mode: :edit,
              fields: fields,
              form: form,
              record: record,
              belongs_to_options: belongs_to_options(fields, actor, record)
            )
        end

      # A record hidden by a filter-based read policy (the default) never
      # raises Forbidden — Ash reports it the same way as a genuinely
      # missing id: `Ash.Error.Invalid` wrapping `Ash.Error.Query.NotFound`
      # (see `Ash.get/3`). Folding that into the same honest state as a
      # real policy Forbidden is deliberate, not a gap: telling the two
      # apart would let a user probe which ids exist (M3/M4).
      {:error, %Ash.Error.Forbidden{}} ->
        forbidden_state(socket)

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
          forbidden_state(socket)
        else
          raise error
        end

      {:error, error} ->
        raise error
    end
  end

  defp no_action_state(socket) do
    assign(socket,
      error: :no_action,
      mode: nil,
      fields: [],
      form: nil,
      record: nil,
      belongs_to_options: %{}
    )
  end

  defp forbidden_state(socket) do
    assign(socket,
      error: :forbidden,
      mode: nil,
      fields: [],
      form: nil,
      record: nil,
      belongs_to_options: %{}
    )
  end

  # Preloads each upload field's belongs_to so the form can show a "current
  # file" link (blueprint §6 point 9 — via `__kumi_attachment_url__/1`).
  defp load_upload_relationships(record, fields, actor) do
    relationship_names =
      fields
      |> Enum.filter(&match?({:upload, _}, &1.widget))
      |> Enum.map(fn %{widget: {:upload, relationship}} -> relationship.name end)

    case relationship_names do
      [] ->
        record

      names ->
        case Ash.load(record, names, actor: actor) do
          {:ok, loaded} -> loaded
          {:error, _reason} -> record
        end
    end
  end

  # `record` is `nil` on create (there is no current value to preserve).
  # On edit, the record's current foreign-key value is always included as
  # an option — even when it falls outside the 100-row window or the
  # options read fails outright — so saving after touching an unrelated
  # field can never blank a value the user didn't touch (M5).
  @doc false
  def belongs_to_options(fields, actor, record) do
    fields
    |> Enum.filter(&match?({:belongs_to, _}, &1.widget))
    |> Map.new(fn %{attribute: attribute, widget: {:belongs_to, relationship}} ->
      current_id = record && Map.get(record, attribute.name)
      options = load_options(relationship.destination, actor)
      {attribute.name, ensure_current_option(options, current_id, relationship, actor)}
    end)
  end

  # ponytail: 100-row window, no search/pagination. Fine for a picklist;
  # once a `belongs_to` destination regularly exceeds ~100 rows this needs
  # a searchable/paginated picker instead of a plain `<select>`.
  defp load_options(destination, actor) do
    case destination |> Ash.Query.sort(:id) |> Ash.Query.limit(100) |> Ash.read(actor: actor) do
      {:ok, records} -> Enum.map(records, &{KumiAdmin.Format.record_label(&1), &1.id})
      {:error, _reason} -> []
    end
  end

  defp ensure_current_option(options, nil, _relationship, _actor), do: options

  defp ensure_current_option(options, current_id, relationship, actor) do
    if Enum.any?(options, fn {_label, id} -> id == current_id end) do
      options
    else
      [{current_option_label(relationship.destination, current_id, actor), current_id} | options]
    end
  end

  # Best-effort label for a current value outside the window — falls back
  # to the truncated id (same heuristic as `Format.record_label/1`) rather
  # than failing the whole form when the individual lookup errors.
  defp current_option_label(destination, id, actor) do
    case Ash.get(destination, id, actor: actor) do
      {:ok, record} -> KumiAdmin.Format.record_label(record)
      {:error, _reason} -> KumiAdmin.Format.truncate_id(id)
    end
  end

  defp select?({:select, _}), do: true
  defp select?({:belongs_to, _}), do: true
  defp select?(_), do: false

  defp select_options({:select, values}, _options),
    do: Enum.map(values, &{Phoenix.Naming.humanize(&1), &1})

  defp select_options({:belongs_to, _relationship}, options), do: options

  defp truthy?(value), do: value in [true, "true", "on"]

  defp upload_config(uploads, {:upload, relationship}), do: Map.get(uploads, relationship.name)
  defp upload_config(_uploads, _widget), do: nil

  defp current_attachment_url(nil, _widget), do: nil

  defp current_attachment_url(record, {:upload, relationship}) do
    case Map.get(record, relationship.name) do
      nil ->
        nil

      %Ash.NotLoaded{} ->
        nil

      attachment ->
        destination = relationship.destination

        if Code.ensure_loaded?(destination) and
             function_exported?(destination, :__kumi_attachment_url__, 1) do
          destination.__kumi_attachment_url__(attachment)
        end
    end
  end

  defp current_attachment_url(_record, _widget), do: nil

  defp translate_error({msg, opts}) when is_list(opts) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error({msg, _opts}), do: msg
  defp translate_error(msg) when is_binary(msg), do: msg

  attr :field, Phoenix.HTML.FormField, required: true
  attr :widget, :any, required: true
  attr :attribute, :any, required: true
  attr :options, :list, default: []
  attr :upload, :any, default: nil
  attr :current_url, :any, default: nil
  attr :text, KumiAdmin.Text, required: true

  # Public (not private) so `belongs_to`/select rendering — including the
  # blank-option omission — is directly unit-testable via
  # `Phoenix.LiveViewTest.render_component/2` (M5), without mounting a
  # LiveView.
  @doc false
  def field_input(assigns) do
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
      <option :if={@attribute.allow_nil?} value=""></option>
      <option
        :for={{label, value} <- select_options(@widget, @options)}
        value={value}
        selected={to_string(@field.value) == to_string(value)}
      >
        {label}
      </option>
    </select>
    <div :if={match?({:upload, _}, @widget)} class="kumi-admin-upload">
      <a :if={@current_url} href={@current_url} class="kumi-admin-current-file">
        {KumiAdmin.Text.string(@text, :current_file)}
      </a>
      <.live_file_input upload={@upload} />
      <p :for={err <- upload_errors(@upload)} class="kumi-admin-field-error">
        {upload_error_message(@text, err)}
      </p>
    </div>
    """
  end

  defp upload_error_message(text, :too_large), do: str(text, :upload_too_large)
  defp upload_error_message(text, :too_many_files), do: str(text, :upload_too_many_files)
  defp upload_error_message(text, :not_accepted), do: str(text, :upload_not_accepted)

  defp upload_error_message(text, reason),
    do: str(text, :upload_failed, reason: inspect(reason))

  defp str(text, key, bindings \\ []), do: KumiAdmin.Text.string(text, key, bindings)

  defp t(socket, key), do: KumiAdmin.Text.string(socket.assigns.text, key)

  def render(assigns) do
    ~H"""
    <Shell.shell
      app={@app}
      text={@text}
      mount_path={@mount_path}
      active_resource={@resource}
      actor={@actor}
      sign_out_path={@sign_out_path}
      flash={@flash}
    >
      <a
        :if={@resource}
        href={"#{@mount_path}/#{KumiAdmin.Slug.for_resource(@resource)}"}
        class="kumi-admin-back-link"
      >
        &larr; {KumiAdmin.Text.string(@text, :back_to,
          name: KumiAdmin.Text.resource(@text, @resource)
        )}
      </a>

      <p :if={@error == :not_found} class="kumi-admin-empty">
        {KumiAdmin.Text.string(@text, :unknown_resource)}
      </p>

      <p :if={@error == :forbidden} class="kumi-admin-empty">
        {KumiAdmin.Text.string(@text, :no_access_or_record)}
      </p>

      <p :if={@error == :no_action} class="kumi-admin-empty">
        {KumiAdmin.Text.string(@text, :unsupported_action)}
      </p>

      <.form
        :if={is_nil(@error)}
        for={@form}
        id="resource-form"
        phx-change="validate"
        phx-submit="save"
      >
        <div :for={field <- @fields} class="kumi-admin-field">
          <label class="kumi-admin-field-label" for={@form[field.attribute.name].id}>
            {KumiAdmin.Text.field(@text, @resource, field.attribute.name)}
          </label>
          <.field_input
            field={@form[field.attribute.name]}
            widget={field.widget}
            attribute={field.attribute}
            options={Map.get(@belongs_to_options, field.attribute.name, [])}
            upload={upload_config(Map.get(assigns, :uploads, %{}), field.widget)}
            current_url={current_attachment_url(@record, field.widget)}
            text={@text}
          />
          <p :for={msg <- @form[field.attribute.name].errors} class="kumi-admin-field-error">
            {translate_error(msg)}
          </p>
        </div>
        <div class="kumi-admin-actions">
          <button type="submit" class="kumi-admin-button">
            {KumiAdmin.Text.string(@text, :save)}
          </button>
        </div>
      </.form>
    </Shell.shell>
    """
  end
end
