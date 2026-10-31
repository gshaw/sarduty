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
  alias App.ViewModel.ActivityFormViewModel
  alias Web.ActivityTemplateLive
  alias Web.Components.PlaceBox

  # Adding and changing activities (docs/records.md, #585). Delete is on the activity's
  # page, in Actions (docs/urls.md). Add activity can start from a template (#747): it
  # fills the form from the template's details, lists what saving adds after, and Save
  # does what Apply a template does, then publishes last. `?template=` picks one.
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
      |> assign_form(ActivityFormViewModel.changeset(form))
      |> pick_on_mount(params["template"])

    {:ok, socket}
  end

  # The template's page links here with it picked. No errors until something is typed.
  defp pick_on_mount(socket, nil), do: socket

  defp pick_on_mount(socket, id) do
    case find_template(socket, id) do
      nil ->
        socket

      template ->
        params = ActivityFormViewModel.template_params(%{}, template)

        socket
        |> picked(template, params)
        |> assign_form(ActivityFormViewModel.changeset(socket.assigns.form_data, params))
    end
  end

  defp find_template(socket, id),
    do: Enum.find(socket.assigns.templates, &(Integer.to_string(&1.id) == id))

  defp picked(socket, template, params) do
    team = socket.assigns.current_team

    fields =
      if template.activity_kind,
        do: CustomField.get_all(team.id, template.activity_kind),
        else: []

    assign(socket,
      template: template,
      params: params,
      filled: socket.assigns.filled + 1,
      template_fields: fields,
      member_counts: GroupMember.counts(team.id)
    )
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
      <.input
        :if={@templates != []}
        field={@form[:template_id]}
        type="select"
        label="Template (optional)"
        options={[{"None", ""} | Enum.map(@templates, &{&1.title, &1.id})]}
      >
        Fills in the form. Saving also adds the template's fields, items, tags, and groups.
      </.input>
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
        <%!-- A template's activity is one evening, so it takes a date and two times. --%>
        <div :if={@template} id="activity-date-times" class="grid md:grid-cols-3 gap-x-6">
          <.input field={@form[:date]} type="date" label="Date" />
          <.input field={@form[:start_time]} type="time" label="Start" />
          <.input field={@form[:finish_time]} type="time" label="Finish" />
        </div>
        <%!-- Side by side only where a date and time fit in half the width. --%>
        <div :if={!@template} class="grid md:grid-cols-2 gap-x-6">
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
      <.input field={@form[:published]} type="checkbox" label="Published">
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

  # What saving adds after the activity, read only (#747). A template's fields go only on
  # an activity of its kind.
  defp template_adds(assigns) do
    assigns =
      assign(assigns,
        field_rows:
          if(assigns.kind == assigns.template.activity_kind,
            do:
              CustomField.rows(
                assigns.fields,
                assigns.template.custom_values,
                assigns.team.timezone,
                restricted: true
              ),
            else: []
          ),
        items:
          assigns.template.template_items
          |> Enum.filter(&EquipmentItem.in_service?(&1.equipment_item))
          |> Enum.sort_by(&String.downcase(&1.equipment_item.title)),
        tags: Template.tags(assigns.template),
        groups: Template.groups(assigns.template)
      )

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
      if event["_target"] == ["form", "template_id"],
        do: pick(socket, params),
        else: socket |> assign(params: params) |> validate(params)

    if event["_target"] == ["form", "place"], do: PlaceBox.typed("activity", params["place"])
    {:noreply, socket}
  end

  def handle_event("save", %{"form" => params}, %{assigns: %{template: %Template{}}} = socket) do
    %{current_team: team, current_user: user} = socket.assigns
    now = DateTime.utc_now()

    case SaveActivity.call(team, nil, params, user, now, hold_publish: true) do
      # The copy hasn't caught up, so the template waits for the activity's page.
      {:ok, nil} ->
        text = "Added #{params["title"]}. Apply the template from its page once it shows."
        path = ~p"/teams/#{team}/activities"
        {:noreply, socket |> put_flash(:error, text) |> push_navigate(to: path)}

      {:ok, activity} ->
        {:noreply, added(socket, activity, params["published"] == "true", now)}

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

  # Picking a template fills the form from it; None goes back to the two date-and-time
  # boxes with the times picked.
  defp pick(socket, params) do
    case find_template(socket, params["template_id"]) do
      nil ->
        # The times as the template's date and two times made them.
        times = Map.put(params, "template_id", socket.assigns.params["template_id"])
        changeset = ActivityFormViewModel.changeset(socket.assigns.form_data, times)

        params =
          Map.merge(params, %{
            "starts_at" => naive_text(Ecto.Changeset.get_field(changeset, :starts_at)),
            "ends_at" => naive_text(Ecto.Changeset.get_field(changeset, :ends_at))
          })

        socket |> assign(template: nil, params: params) |> validate(params)

      template ->
        params = ActivityFormViewModel.template_params(params, template)
        socket |> picked(template, params) |> validate(params)
    end
  end

  defp naive_text(nil), do: nil

  defp naive_text(naive),
    do: naive |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

  # The template's steps on the new activity, then Published, then its page with one flash.
  defp added(socket, activity, published?, now) do
    %{current_team: team, current_user: user, template: template} = socket.assigns

    {kind, lines} =
      team
      |> add_template(user, activity, template, now)
      |> publish_last(published?, activity, socket)

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

  # Published goes last, once the fields and members have gone, since D4H locks them. A
  # refusal before it leaves the activity unpublished.
  defp publish_last(result, false = _published?, _activity, _socket), do: result

  defp publish_last({:info, lines}, true, activity, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case SaveActivity.publish(team, activity, user, DateTime.utc_now()) do
      {:ok, _activity} -> {:info, lines}
      {:error, error} -> {:error, lines ++ ["It was not published.", error]}
    end
  end

  defp publish_last({kind, lines}, true, _activity, _socket),
    do: {kind, Enum.concat(lines, ["It was not published."])}

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
