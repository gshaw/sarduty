defmodule Web.WhiteboardNoteFormLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Model.WhiteboardNote
  alias App.Operation.SaveWhiteboardNote
  alias App.ViewModel.WhiteboardNoteFormViewModel

  # Post a note and Change note (#515), for team admins. /whiteboard/new?from=<id> is Post
  # again: an old note's text, link, and Important, with a new Show until. The form is the
  # app layout's, not narrow: it isn't done with a device in hand.
  def mount(params, _session, socket) do
    team = socket.assigns.current_team
    if !Team.whiteboard?(team), do: raise(Web.Status.NotFound)
    today = Service.Period.today(DateTime.utc_now(), team.timezone)

    {note, form} =
      case {socket.assigns.live_action, params} do
        {:edit, %{"id" => id}} ->
          note = find_team_note!(team, id)
          {note, WhiteboardNoteFormViewModel.from_note(note, team.timezone, today)}

        {:new, %{"from" => id}} ->
          {nil, team |> find_team_note!(id) |> WhiteboardNoteFormViewModel.again(today)}

        {:new, _params} ->
          {nil, WhiteboardNoteFormViewModel.new(today)}
      end

    socket
    |> assign(
      page_title: if(note, do: "Change note", else: "Post a note"),
      note: note,
      form_data: form,
      today: today
    )
    |> assign_form(WhiteboardNoteFormViewModel.changeset(form, %{}, today))
    |> then(&{:ok, &1})
  end

  defp find_note!(team, id) do
    with {id, ""} <- Integer.parse(id),
         %WhiteboardNote{} = note <- WhiteboardNote.get_for_team(team, id) do
      note
    else
      _missing -> raise Web.Status.NotFound
    end
  end

  # An organization's note is read-only to its teams, and not theirs to post again.
  defp find_team_note!(team, id) do
    note = find_note!(team, id)
    if !WhiteboardNote.team_note?(note), do: raise(Web.Status.NotFound)
    note
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "note"))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Whiteboard" path={~p"/teams/#{@current_team}/whiteboard"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p class="lead">{lead(@current_team)}</p>

    <.form
      for={@form}
      id="whiteboard-note-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <.error_summary form={@form} />
      <.input field={@form[:text]} type="textarea" label="Note" rows="3" maxlength="140">
        Up to 140 characters.
      </.input>
      <.input field={@form[:url]} type="url" label="Link (optional)">
        A page with more, like https://example.com/agm.
      </.input>
      <.input
        field={@form[:until]}
        type="date"
        label="Show until"
        min={Date.to_iso8601(Date.add(@today, 1))}
      >
        It leaves the whiteboard after this day. {D4H.service_name(@current_team)} keeps it.
      </.input>
      <.input field={@form[:important]} type="checkbox" label="Important">
        It shows first, with an Important tag.
      </.input>
      <.form_actions>
        <.button
          id="whiteboard-note-save"
          variant={:success}
          phx-disable-with={"Sending to #{D4H.service_name(@current_team)}…"}
        >
          {if @note, do: "Save note", else: "Post note"}
        </.button>
        <.button id="whiteboard-note-cancel" navigate={~p"/teams/#{@current_team}"}>Cancel</.button>
      </.form_actions>
    </.form>

    <section :if={@note} id="whiteboard-note-delete" class="mt-8 measure">
      <h2 class="heading">Delete the note</h2>
      <p>
        {gone_text(@current_team)} To keep it under Archived, archive it instead.
      </p>
      <.button
        id="whiteboard-note-delete-button"
        phx-disable-with="Deleting…"
        type="button"
        variant={:danger}
        phx-click="delete"
        data-confirm={"Delete this note? #{gone_text(@current_team)}"}
      >
        Delete note
      </.button>
    </section>
    """
  end

  defp lead(team) do
    if D4H.records?(team),
      do: "Everyone on the team reads it on the Dashboard.",
      else: "Everyone on the team reads it on the Dashboard and in #{D4H.service_name(team)}."
  end

  @doc "What a delete does, naming the team's service."
  def gone_text(team), do: "It's gone for good, from SAR Duty and #{D4H.service_name(team)}."

  def handle_event("validate", %{"note" => params}, socket) do
    %{form_data: form, today: today} = socket.assigns

    changeset =
      form |> WhiteboardNoteFormViewModel.changeset(params, today) |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"note" => params}, socket) do
    %{current_team: team, current_user: user, note: note} = socket.assigns
    %{form_data: form, today: today} = socket.assigns

    with {:ok, values} <- WhiteboardNoteFormViewModel.validate(form, params, today),
         {:ok, _saved} <- save(team, user, note, values) do
      {:noreply, push_navigate(socket, to: ~p"/teams/#{team}")}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{current_team: team, current_user: user, note: note} = socket.assigns

    case SaveWhiteboardNote.delete(team, user, note) do
      {:ok, _note} -> {:noreply, push_navigate(socket, to: ~p"/teams/#{team}")}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp save(team, user, nil, values), do: SaveWhiteboardNote.post(team, user, values)
  defp save(team, user, note, values), do: SaveWhiteboardNote.change(team, user, note, values)
end
