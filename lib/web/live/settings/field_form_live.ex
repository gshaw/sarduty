defmodule Web.Settings.FieldFormLive do
  use Web, :live_view_app_layout

  import Web.Components.DragList
  import Web.FieldText

  alias App.Model.CustomField
  alias App.Model.CustomFieldBundle
  alias App.Model.Team
  alias App.Operation.ChangeCustomField
  alias App.Operation.CreateCustomField
  alias App.Repo
  alias App.ViewModel.CustomFieldFormViewModel

  # Add field, /teams/:subdomain/settings/fields/new?kind=incident, and Change field,
  # /teams/:subdomain/settings/fields/:id/edit (#1056 step 4): one of the team's own
  # fields. The rules are CustomFieldFormViewModel's, and the operations send the change
  # set. Kind and type are set once, so Change field shows them as facts. Choices are
  # renamed, dragged into order, archived, restored, and added, never deleted. The form
  # only saves: deleting, archiving, and restoring the field are on its page.
  def mount(params, _session, socket) do
    team = Repo.preload(socket.assigns.current_team, :organization)
    field = load_field(team, params["id"])
    form = if field, do: CustomFieldFormViewModel.from_field(field), else: new_form(params)

    socket =
      socket
      |> assign(
        page_title: if(field, do: "Change field", else: "Add field"),
        field: field,
        base: form,
        fields: CustomField.get_all_with_archived(team.id),
        bundles: CustomFieldBundle.get_all(team.id),
        organization_name: team.organization && team.organization.short_name,
        answer_count: field && CustomField.answer_count(field)
      )
      |> assign_form(%{}, nil)

    {:ok, socket}
  end

  # A team admin reaches only a field the team changes, with a key that can.
  defp load_field(team, nil) do
    if !Team.d4h_can?(team, :custom_fields), do: raise(Web.Status.NotFound)
    nil
  end

  defp load_field(team, id) do
    field = team.id |> CustomField.get_for_team!(id) |> Repo.preload(:bundle)
    if !CustomField.team_changes?(team, field), do: raise(Web.Status.NotFound)
    field
  end

  defp new_form(params) do
    target = if params["kind"] in CustomField.targets(), do: params["kind"], else: "incident"
    CustomFieldFormViewModel.new(target)
  end

  # `params` are the form's as last posted, with choices as a list. A choice field always
  # has a box to type its first choice in.
  defp assign_form(socket, params, action) do
    %{base: base, fields: fields, field: field} = socket.assigns

    changeset =
      base
      |> CustomFieldFormViewModel.changeset(params, fields, field)
      |> Map.put(:action, action)

    choices = Ecto.Changeset.get_field(changeset, :choices)
    type = Ecto.Changeset.get_field(changeset, :field_type)

    if type in ~w(single_choice multiple_choice) and choices == [] do
      assign_form(socket, Map.put(params, "choices", [blank_choice()]), action)
    else
      assign(socket,
        params: Map.put(params, "choices", choices),
        changeset: changeset,
        form: to_form(changeset, as: "field")
      )
    end
  end

  defp blank_choice, do: %{"id" => nil, "label" => "", "archived" => false}

  def render(assigns) do
    form = assigns.changeset
    target = Ecto.Changeset.get_field(form, :target)
    type = Ecto.Changeset.get_field(form, :field_type)

    assigns =
      assign(assigns,
        target: target,
        type: type,
        choices: Ecto.Changeset.get_field(form, :choices),
        choice?: type in ~w(single_choice multiple_choice),
        bundle_options:
          for(
            b <- assigns.bundles,
            b.owner_type == "Team" and b.target == target,
            do: {b.title, b.title}
          ),
        fields_path: ~p"/teams/#{assigns.current_team}/settings/fields?kind=#{target}"
      )

    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label="Fields" path={@fields_path} />
      <:item
        :if={@field}
        label={@field.title}
        path={~p"/teams/#{@current_team}/settings/fields/#{@field.id}"}
      />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p :if={@field} id="field-facts" class="lead">
      {CustomField.type_label(@field.field_type)}, on {String.downcase(
        CustomField.target_title(@field.target)
      )}. {answers(@field.target, @answer_count)}
    </p>

    <.form
      for={@form}
      id="field-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <.error_summary form={@form} />
      <.input
        :if={!@field}
        field={@form[:target]}
        type="select"
        label="On"
        options={for t <- CustomField.targets(), do: {CustomField.target_title(t), t}}
      >
        The kind of record the field is on. It cannot change later.
      </.input>
      <.input field={@form[:title]} label="Name" autocomplete="off">
        {if @field,
          do: "A new name shows on every #{noun(@target)}, old ones too.",
          else: "A question or a label, such as Debrief held."}
      </.input>

      <.input
        :if={!@field}
        field={@form[:field_type]}
        type="combobox"
        label="Type"
        placeholder="Select a type"
        keyboard={false}
        options={
          for t <- CustomFieldFormViewModel.types(),
              do: [key: CustomField.type_label(t), value: t, "data-hint": type_hint(t)]
        }
      >
        A field's type cannot change later.
        <:below>
          <p :if={@type} id="field-type-hint" class="hint mt-1">{type_hint(@type)}</p>
        </:below>
      </.input>

      <.choices_input
        :if={@choice?}
        form={@form}
        choices={@choices}
        changing={@field != nil}
        noun={noun(@target)}
      />

      <.input
        :if={@type == "number"}
        field={@form[:value_units]}
        label="Units (optional)"
        autocomplete="off"
      >
        Such as km or hours. Up to {Service.Format.characters(10)}.
      </.input>

      <.input field={@form[:hint]} type="textarea" label="What it means (optional)">
        Shown under the name when someone fills it in. Reports and AI agents read it too.
      </.input>

      <.input
        field={@form[:bundle]}
        type="combobox"
        label="Bundle (optional)"
        free_text
        options={@bundle_options}
      >
        A heading that groups your team's fields on a record. Type a new name to add one.
      </.input>

      <.input
        :if={CustomField.activity_target?(@target)}
        field={@form[:required]}
        type="checkbox"
        label="Needed to publish"
      >
        An {noun(@target)} cannot be published while this is empty. A draft can leave it empty.
      </.input>
      <.input
        :if={CustomField.restricted_matters?(@target)}
        field={@form[:restricted]}
        type="checkbox"
        label="Restricted"
      >
        Only team admins see its values. {restricted_who(@organization_name)}
      </.input>

      <.input
        :if={@target == "member"}
        field={@form[:member_privacy]}
        type="radios"
        label="Each member's own answer"
        options={[
          {"Hidden from them", "hidden", "Only team admins see it."},
          {"They see it", "viewable", "On Your membership."},
          {"They see and change it", "editable", "On Your membership."}
        ]}
      >
        Team admins see every member's answer. A member never sees another member's.
      </.input>

      <.form_actions>
        <.button id="field-save" variant={:success} phx-disable-with="Saving…">
          {if @field, do: "Save field", else: "Add field"}
        </.button>
        <.button
          id="field-cancel"
          navigate={
            if @field,
              do: ~p"/teams/#{@current_team}/settings/fields/#{@field.id}",
              else: @fields_path
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :choices, :list, required: true
  attr :changing, :boolean, required: true
  attr :noun, :string, required: true

  # A box for each choice, in order. A new one is removed; one the field has is archived,
  # since D4H can't delete it, and shows greyed with Restore.
  defp choices_input(assigns) do
    # Only after a save: a choice just added is blank while it waits to be typed.
    errors =
      if assigns.form.source.action in [:insert, :update],
        do: assigns.form[:choices].errors,
        else: []

    assigns = assign(assigns, :errors, Enum.map(errors, &translate_error/1))

    ~H"""
    <fieldset id="field-choices" class="mb-6">
      <legend class="font-semibold">Choices</legend>
      <p class="hint mb-2">
        {if @changing,
          do:
            "A renamed choice changes on every #{@noun} that has it. An archived choice is no longer offered, and #{@noun}s that have it keep it.",
          else: "In the order people see them."}
      </p>
      <.drag_list
        :let={{choice, index}}
        id="field-choice-list"
        class="mb-2"
        rows={Enum.with_index(@choices)}
        key={&choice_key/1}
        label={&choice_label/1}
        event="reorder-choices"
      >
        <input type="hidden" name={"field[choices][#{index}][id]"} value={choice["id"]} />
        <input
          type="hidden"
          name={"field[choices][#{index}][archived]"}
          value={to_string(choice["archived"])}
        />
        <input
          type="text"
          id={"field-choice-#{index}-label"}
          name={"field[choices][#{index}][label]"}
          value={choice["label"]}
          aria-label={"Choice #{index + 1}"}
          readonly={choice["archived"]}
          class={["grow", choice["archived"] && "text-text-muted"]}
          autocomplete="off"
        />
        <.badge :if={choice["archived"]}>Archived</.badge>
        <.button
          :if={is_nil(choice["id"])}
          id={"field-choice-#{index}-remove"}
          type="button"
          size={:sm}
          phx-click="remove-choice"
          phx-value-index={index}
        >
          Remove
        </.button>
        <.button
          :if={choice["id"] && !choice["archived"]}
          id={"field-choice-#{index}-archive"}
          type="button"
          size={:sm}
          phx-click="archive-choice"
          phx-value-index={index}
        >
          Archive
        </.button>
        <.button
          :if={choice["id"] && choice["archived"]}
          id={"field-choice-#{index}-restore"}
          type="button"
          size={:sm}
          phx-click="restore-choice"
          phx-value-index={index}
        >
          Restore
        </.button>
      </.drag_list>
      <.error :for={message <- @errors}>{message}</.error>
      <.button id="field-add-choice" type="button" size={:sm} phx-click="add-choice">
        Add choice
      </.button>
    </fieldset>
    """
  end

  # A choice the field has keeps its key as it moves; a new one goes by its place.
  defp choice_key({%{"id" => nil}, index}), do: "new-#{index}"
  defp choice_key({%{"id" => id}, _index}), do: "option-#{id}"

  defp choice_label({%{"label" => label}, _index}) when label not in [nil, ""], do: label
  defp choice_label({_choice, index}), do: "choice #{index + 1}"

  @doc "A line under each type in the picker, on what it holds."
  def type_hint("text"), do: "A line of text."
  def type_hint("text_area"), do: "Text that can run to several lines."
  def type_hint("number"), do: "A number, with units if you like."
  def type_hint("date"), do: "A day."
  def type_hint("datetime"), do: "A day and a time."
  def type_hint("time"), do: "A time of day."
  def type_hint("single_choice"), do: "Pick one from a list."
  def type_hint("multiple_choice"), do: "Pick any number from a list."
  def type_hint(_type), do: nil

  defp restricted_who(nil), do: "Members do not."
  defp restricted_who(organization), do: "Members and #{organization} do not."

  def handle_event("validate", %{"field" => params}, socket),
    do: {:noreply, assign_form(socket, params, :validate)}

  def handle_event(event, params, socket)
      when event in ~w(add-choice remove-choice archive-choice restore-choice),
      do: {:noreply, update_choices(socket, &change_choices(event, &1, params["index"]))}

  def handle_event("reorder-choices", %{"keys" => keys}, socket) do
    choices = Enum.with_index(socket.assigns.params["choices"])

    case reorder(choices, keys, &choice_key/1) do
      {:ok, moved} ->
        {:noreply, update_choices(socket, fn _ -> Enum.map(moved, &elem(&1, 0)) end)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"field" => params}, socket), do: save_field(socket, params)

  defp save_field(socket, params) do
    %{current_team: team, current_user: user, field: field} = socket.assigns

    case save(team, user, field, params) do
      {:ok, saved} ->
        socket
        |> put_flash(:info, saved_text(field, saved || field, params))
        |> push_navigate(to: saved_path(team, saved, params))
        |> then(&{:noreply, &1})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset, form: to_form(changeset, as: "field"))}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp save(team, user, nil, params),
    do:
      CreateCustomField.call(
        team,
        user,
        Map.put_new(params, "target", "incident"),
        DateTime.utc_now()
      )

  defp save(team, user, field, params),
    do: ChangeCustomField.call(team, user, field, params, DateTime.utc_now())

  defp update_choices(socket, fun) do
    params = Map.update!(socket.assigns.params, "choices", fun)
    assign_form(socket, params, socket.assigns.changeset.action)
  end

  defp change_choices("add-choice", choices, _index),
    do: List.insert_at(choices, -1, blank_choice())

  defp change_choices("remove-choice", choices, index),
    do: List.delete_at(choices, String.to_integer(index))

  defp change_choices(event, choices, index) do
    archived? = event == "archive-choice"
    List.update_at(choices, String.to_integer(index), &Map.put(&1, "archived", archived?))
  end

  defp saved_text(nil, nil, params), do: "Added the #{params["title"]} field."
  defp saved_text(nil, saved, _params), do: "Added the #{saved.title} field."
  defp saved_text(_field, saved, _params), do: "Saved the #{saved.title} field."

  # Nil when D4H's answer couldn't be read and the sync will copy the field.
  defp saved_path(team, nil, params),
    do: ~p"/teams/#{team}/settings/fields?kind=#{params["target"] || "incident"}"

  defp saved_path(team, saved, _params), do: ~p"/teams/#{team}/settings/fields/#{saved.id}"
end
