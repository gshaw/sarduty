defmodule Web.ActivityFormLive do
  use Web, :live_view_app_layout

  import Web.Components.CustomFields, only: [missing_text: 1, custom_fields_table: 1]
  import Web.TemplateLive, only: [items_table: 1, groups_table: 1]

  alias App.Model.Activity
  alias App.Model.CustomField
  alias App.Model.EquipmentItem
  alias App.Model.GroupMember
  alias App.Model.Template
  alias App.Operation.SaveActivity
  alias App.Operation.SaveCustomFields
  alias App.ViewModel.ActivityFormViewModel
  alias Web.ActivityTemplateLive
  alias Web.Components.PlaceBox

  # Adding and changing activities (docs/records.md, #585). Delete is on the activity's
  # page, in Actions (docs/urls.md). Add activity can start from a template (#747): it
  # fills the form from the template's details, lists what saving adds after, and Save
  # does what Apply a template does. `?template=` picks one. Picking another starts the
  # form over, and asks first when anything was changed, so two templates never mix.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    activity = if id = params["id"], do: Activity.find!(team, id)
    if activity && activity.deleted_at, do: raise(Web.Status.NotFound)

    form = ActivityFormViewModel.from_activity(activity, team)

    socket =
      socket
      |> assign(page_title: page_title(activity, socket.assigns.live_action))
      |> assign(activity: activity, form_data: form)
      |> assign(params: %{})
      |> assign(fields: activity && fields(team, activity))
      |> assign(
        description_locked?: ActivityFormViewModel.description_locked?(activity),
        published_locked?: activity != nil and Activity.locked?(activity)
      )
      |> assign(templates: if(activity, do: [], else: Template.get_all(team.id)))
      |> assign(template: nil, filled: 0, member_counts: %{}, template_fields: [])
      # The params the form started from, and the template a pick waits on (#747).
      |> assign(started: %{}, switch_to: nil)
      |> assign_form(ActivityFormViewModel.changeset(form))
      |> pick_on_mount(params["template"])

    {:ok, socket}
  end

  # The template's page links here with it picked. No errors until something is typed.
  defp pick_on_mount(socket, nil), do: socket

  defp pick_on_mount(socket, id) do
    case find_template(socket, id) do
      nil -> socket
      template -> start_over(socket, template)
    end
  end

  defp find_template(socket, id),
    do: Enum.find(socket.assigns.templates, &(Integer.to_string(&1.id) == id))

  # The form from `template`, or empty for :none, with no errors until something is typed.
  defp start_over(socket, :none), do: socket |> assign(template: nil) |> reset(%{})

  defp start_over(socket, template) do
    team = socket.assigns.current_team

    fields =
      if template.activity_kind,
        do: CustomField.get_all(team.id, template.activity_kind),
        else: []

    socket
    |> assign(
      template: template,
      template_fields: fields,
      member_counts: GroupMember.counts(team.id)
    )
    |> reset(ActivityFormViewModel.template_params(template, today(socket)))
  end

  # A new id draws the description's editor again.
  defp reset(socket, params) do
    socket
    |> assign(params: params, started: params, switch_to: nil, filled: socket.assigns.filled + 1)
    |> assign_form(ActivityFormViewModel.changeset(socket.assigns.form_data, params))
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        :if={@activity}
        label={@activity.ref_id}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={breadcrumb(@live_action)} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <.form
      for={@form}
      id="activity-form"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.error_summary form={@form} />
      <%!-- Set apart, so the template reads as what fills the form, not part of it. --%>
      <section :if={@templates != []} id="activity-template-box" class="card card-alt mb-8">
        <h2 id="activity-template-heading" class="heading">Start from a template</h2>
        <.input
          field={@form[:template_id]}
          type="select"
          aria-labelledby="activity-template-heading"
          options={[{"None", ""} | Enum.map(@templates, &{&1.title, &1.id})]}
        >
          Optional. Fills in the form below.
        </.input>
        <p :if={@template} id="activity-template-summary" class="mt-3">
          {adds_text(
            adds(@template, @form[:kind].value, @template_fields, @current_team),
            passed_text(@form, @current_team)
          )}
        </p>
      </section>
      <h2 :if={@templates != []} class="heading">Activity</h2>
      <.warning_text :if={@published_locked?} id="activity-published-locked" class="mb-6">
        A published activity cannot be changed. Untick Published and save first.
      </.warning_text>
      <%!-- A disabled fieldset sends none of its fields. --%>
      <fieldset disabled={@published_locked?}>
        <.input
          :if={!@activity}
          field={@form[:kind]}
          type="select"
          label="Kind"
          options={ActivityFormViewModel.kinds()}
        />
        <.input field={@form[:title]} label="Title" />
        <%!-- Side by side only where a date and time fit in half the width. --%>
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:starts_at]} type="datetime-local" label="Start" />
          <.input field={@form[:ends_at]} type="datetime-local" label="Finish" />
        </div>
        <.live_component
          module={PlaceBox}
          id="activity"
          team={@current_team}
          field={@form[:place]}
          coordinate={@form[:coordinate]}
          label="Address (optional)"
          kind={PlaceBox.map_kind(@form[:kind].value)}
        />
        <.input
          field={@form[:hours]}
          type="select"
          label="Tax credit hours"
          options={ActivityFormViewModel.hours()}
        >
          Which hours the activity counts for on tax credit letters.
        </.input>
        <.input field={@form[:tracking_number]} label="Tracking number (optional)" />
        <div :if={@description_locked?} id="activity-description-locked" class="mb-6">
          <.label>Description</.label>
          <.hint>
            Change the description in {@service}. It has things this form cannot keep, such as a table or a picture.
          </.hint>
          <.markdown content={@activity.description} />
        </div>
        <%!-- A new id draws the editor again with what a template filled in. --%>
        <.input
          :if={!@description_locked?}
          id={@filled > 0 && "form_description_#{@filled}"}
          field={@form[:description]}
          type="rich_text"
          label="Description (optional)"
        />
      </fieldset>
      <.template_adds
        :if={@template}
        template={@template}
        kind={@form[:kind].value}
        fields={@template_fields}
        member_counts={@member_counts}
        passed={passed_text(@form, @current_team)}
        team={@current_team}
      />
      <%!-- With a template, publishing is a second step, once what it added is checked. --%>
      <.input :if={!@template} field={@form[:published]} type="checkbox" label="Published">
        Attendance cannot be changed once the activity is published.
      </.input>
      <.form_actions>
        <.button variant={:success} phx-disable-with={if @activity, do: "Saving…", else: "Adding…"}>
          {if @activity, do: "Save activity", else: "Add activity"}
        </.button>
        <.button
          id="activity-cancel"
          navigate={
            if @activity,
              do: ~p"/teams/#{@current_team}/activities/#{@activity.id}",
              else: ~p"/teams/#{@current_team}/activities"
          }
        >
          Cancel
        </.button>
      </.form_actions>
    </.form>
    <%!-- Outside the form: the dialog has a form of its own. --%>
    <.confirm_dialog
      :if={@switch_to}
      id="activity-template-switch"
      phx-hook="AskDialog"
      data-confirm-event="start-over"
      data-cancel-event="keep-changes"
      question={switch_question(@switch_to)}
      body={switch_body(@switch_to)}
      action="Start over"
    />

    <section :if={@live_action == :edit && @fields} id="activity-fields" class="mt-8 measure">
      <h2 class="heading">Fields</h2>
      <p :if={@fields.missing} id="activity-fields-missing-count">
        {missing_text(@fields.missing)}
      </p>
      <p class="action">
        <.a
          id="activity-fields-change"
          navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/fields/edit"}
        >Change fields</.a>
      </p>
    </section>
    """
  end

  attr :template, :map, required: true
  attr :kind, :string, required: true, doc: "the kind the form holds now"
  attr :fields, :list, required: true, doc: "the template's kind's custom fields"
  attr :member_counts, :map, required: true
  attr :passed, :string, required: true, doc: "nil, or why the groups are left out"
  attr :team, :map, required: true

  # What saving adds after the activity, read only (#747).
  defp template_adds(assigns) do
    assigns =
      assign(assigns, adds(assigns.template, assigns.kind, assigns.fields, assigns.team))

    ~H"""
    <section
      :if={@field_rows != [] or @items != [] or @tags != [] or @groups != []}
      id="activity-template-adds"
      class="mb-6"
    >
      <h2 class="heading">{@template.title} adds</h2>
      <p class="hint mb-4">Change them on the activity once it is added.</p>
      <div :if={@field_rows != []} class="mb-4">
        <h3 class="subheading">Fields · {length(@field_rows)}</h3>
        <.custom_fields_table id="activity-template-fields" rows={@field_rows} />
      </div>
      <div :if={@items != []} class="mb-4">
        <h3 class="subheading">Items · {length(@items)}</h3>
        <.items_table id="activity-template-items" items={@items} team={@team} link={false} />
      </div>
      <div :if={@tags != []} id="activity-template-tags" class="mb-4">
        <h3 class="subheading">Tags · {length(@tags)}</h3>
        <span class="badges">
          <.badge :for={tag <- @tags} kind={:outline}>{tag.title}</.badge>
        </span>
      </div>
      <div :if={@groups != [] and !@passed} class="mb-4">
        <h3 class="subheading">Groups · {length(@groups)}</h3>
        <p class="hint mb-2">Each member is added as No reply. Nobody is emailed.</p>
        <.groups_table
          id="activity-template-groups"
          groups={@groups}
          member_counts={@member_counts}
          team={@team}
          link={false}
        />
      </div>
      <.warning_text :if={@groups != [] and @passed} id="activity-template-groups-passed">
        The groups will be left out: {@passed}
      </.warning_text>
    </section>
    """
  end

  # A template's fields go only on an activity of its kind.
  defp adds(template, kind, fields, team) do
    %{
      field_rows:
        if(kind == template.activity_kind,
          do:
            CustomField.rows(
              fields,
              SaveCustomFields.fill_empty(%{}, %Activity{}, fields, template.custom_values),
              team.timezone,
              restricted: true
            ),
          else: []
        ),
      items:
        template.template_items
        |> Enum.filter(&EquipmentItem.in_service?(&1.equipment_item))
        |> Enum.sort_by(&String.downcase(&1.equipment_item.title)),
      tags: Template.tags(template),
      groups: Template.groups(template)
    }
  end

  # The box's one line on what the list under the form holds: "Saving also adds 2 fields,
  # 1 tag, and the members of 2 groups, listed under the form." Nil when it adds nothing.
  defp adds_text(adds, passed) do
    parts =
      Enum.filter(
        [
          adds.field_rows != [] &&
            Service.Format.count(length(adds.field_rows), one: "%d field", many: "%d fields"),
          adds.items != [] &&
            Service.Format.count(length(adds.items), one: "%d item", many: "%d items"),
          adds.tags != [] &&
            Service.Format.count(length(adds.tags), one: "%d tag", many: "%d tags"),
          adds.groups != [] && !passed &&
            "the members of " <>
              Service.Format.count(length(adds.groups), one: "%d group", many: "%d groups")
        ],
        & &1
      )

    if parts != [],
      do: "Saving also adds #{Service.Format.and_list(parts)}, listed under the form."
  end

  # Members are only added before the start, as with Apply a template: "Oct 26 has
  # passed." for a day gone, "19:00 has passed." for earlier today.
  defp passed_text(form, team) do
    with %Ecto.Changeset{} = changeset <- form.source,
         %NaiveDateTime{} = starts_at <- Ecto.Changeset.get_field(changeset, :starts_at) do
      day = NaiveDateTime.to_date(starts_at)
      start = Service.Convert.local_to_utc(day, NaiveDateTime.to_time(starts_at), team.timezone)
      now = DateTime.utc_now()
      {today, _time} = Service.Convert.utc_to_local(now, team.timezone)

      cond do
        DateTime.after?(start, now) ->
          nil

        Date.before?(day, today) ->
          "#{Service.Format.month_day(start, team.timezone)} has passed."

        true ->
          "#{Service.Format.time_short(start, team.timezone)} has passed."
      end
    else
      _no_start -> nil
    end
  end

  # Change activity's Fields section (#705): the kind's D4H custom fields are on their own
  # page, with the Fields tab's count over a draft incident's missing ones. Nil for an
  # activity with no fields.
  defp fields(team, activity) do
    case CustomField.get_all(team.id, activity.activity_kind) do
      [] -> nil
      fields -> %{missing: CustomField.missing_count(fields, activity, team.timezone)}
    end
  end

  defp page_title(nil, :new), do: "Add activity"
  defp page_title(activity, :edit), do: "Change #{activity.title}"

  defp breadcrumb(:new), do: "Add activity"
  defp breadcrumb(:edit), do: "Change"

  def handle_event("validate", %{"form" => params} = event, socket) do
    socket =
      case {event["_target"], socket.assigns.template} do
        {["form", "template_id"], _template} ->
          pick(socket, params)

        # While a template is picked, Finish keeps its length after Start.
        {["form", "starts_at"], %Template{} = template} ->
          typed(socket, ActivityFormViewModel.follow_start(params, template))

        _other ->
          typed(socket, params)
      end

    if event["_target"] == ["form", "place"], do: PlaceBox.typed("activity", params["place"])
    {:noreply, socket}
  end

  def handle_event("start-over", _params, socket),
    do: {:noreply, start_over(socket, socket.assigns.switch_to)}

  # The template stays as it was picked.
  def handle_event("keep-changes", _params, socket) do
    id = if template = socket.assigns.template, do: Integer.to_string(template.id), else: ""
    params = Map.put(socket.assigns.params, "template_id", id)
    {:noreply, socket |> assign(switch_to: nil) |> typed(params)}
  end

  def handle_event("save", %{"form" => params}, %{assigns: %{template: %Template{}}} = socket) do
    %{current_team: team, current_user: user} = socket.assigns
    now = DateTime.utc_now()

    case SaveActivity.call(team, nil, params, user, now) do
      # The copy hasn't caught up, so the template waits for the activity's page.
      {:ok, nil} ->
        text = "Added #{params["title"]}. Apply the template from its page once it shows."
        path = ~p"/teams/#{team}/activities"
        {:noreply, socket |> put_flash(:error, text) |> push_navigate(to: path)}

      {:ok, activity} ->
        {:noreply, added(socket, activity, now)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, text} ->
        {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("save", %{"form" => params}, socket) do
    %{current_team: team, current_user: user, activity: activity} = socket.assigns

    case SaveActivity.call(team, activity, params, user, DateTime.utc_now()) do
      {:ok, saved} -> {:noreply, saved(socket, saved, saved_text(activity, params))}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  # Picking a template, or None, starts the form over. When anything was changed since
  # the form started, a dialog asks first: Start over, or Cancel to keep the changes.
  defp pick(socket, params) do
    target = find_template(socket, params["template_id"]) || :none

    cond do
      target == (socket.assigns.template || :none) -> typed(socket, params)
      edited?(socket, params) -> socket |> assign(switch_to: target) |> typed(params)
      true -> start_over(socket, target)
    end
  end

  defp switch_question(:none), do: "Start over with no template?"
  defp switch_question(template), do: "Start over with #{template.title}?"

  defp switch_body(:none), do: "The form empties, and your changes are lost."

  defp switch_body(template),
    do: "The form fills in from #{template.title}, and your changes are lost."

  # What the form holds, less the template picked and the description editor's markup.
  defp edited?(socket, params),
    do: values(socket, params) != values(socket, socket.assigns.started)

  defp values(socket, params) do
    socket.assigns.form_data
    |> ActivityFormViewModel.changeset(Map.delete(params, "template_id"))
    |> Ecto.Changeset.apply_changes()
    |> Map.update!(:description, &(&1 && Service.DescriptionHTML.clean(&1)))
  end

  defp typed(socket, params), do: socket |> assign(params: params) |> validate(params)

  defp today(socket) do
    {today, _time} =
      Service.Convert.utc_to_local(DateTime.utc_now(), socket.assigns.current_team.timezone)

    today
  end

  # The template's steps on the new activity, then its page with one flash.
  defp added(socket, activity, now) do
    %{current_team: team, current_user: user, template: template} = socket.assigns
    {kind, lines} = add_template(team, user, activity, template, now)

    text = Enum.join(["Added #{activity.title}." | lines], " ")
    path = ~p"/teams/#{team}/activities/#{activity.id}"
    socket |> put_flash(kind, text) |> push_navigate(to: path)
  end

  # What Apply a template does, on the new activity: `{flash_kind, lines}`.
  defp add_template(team, user, activity, template, now) do
    fields = CustomField.get_all(team.id, activity.activity_kind)
    adds = ActivityTemplateLive.template_adds(template, activity, fields)

    case ActivityTemplateLive.send_all(team, user, activity, adds, now) do
      {:ok, kind, ""} -> {kind, []}
      {:ok, kind, text} -> {kind, [text]}
      {:error, text} -> {:error, [text]}
    end
  end

  # A place picked, or its pin removed (#610).
  def handle_info({PlaceBox, values}, socket) do
    params = Map.merge(socket.assigns.params, values)
    {:noreply, socket |> assign(params: params) |> validate(params)}
  end

  defp saved_text(nil, params), do: "Added #{params["title"]}."
  defp saved_text(_activity, params), do: "Saved #{params["title"]}."

  # The activity's page, or the list when the copy hasn't caught up yet.
  defp saved(socket, activity, text) do
    team = socket.assigns.current_team

    path =
      if activity,
        do: ~p"/teams/#{team}/activities/#{activity.id}",
        else: ~p"/teams/#{team}/activities"

    socket |> put_flash(:info, text) |> push_navigate(to: path)
  end

  defp validate(socket, params) do
    changeset =
      socket.assigns.form_data
      |> ActivityFormViewModel.changeset(params)
      |> Map.put(:action, :validate)

    assign_form(socket, changeset)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "form"))
end
