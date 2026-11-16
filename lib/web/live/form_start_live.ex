defmodule Web.FormStartLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop

  alias App.Operation.AskAI
  alias App.Operation.SaveForm
  alias Web.FormOwner

  # New form on a team's Forms tab (#1083): its name and the agency's PDF. It saves off,
  # with no text, and stays off until it's written. An organization's forms are uploaded
  # instead (Web.FormUploadLive).
  #
  # With AI writing open (#1089), it takes What it's for too, and Write form opens Change
  # form with it as the first ask, already running, or "Write this form." without it.
  # The ask goes in the flash, so a reload of Change form never asks again.
  @max_for 500
  def mount(_params, _session, socket) do
    team = FormOwner.get(socket.assigns)
    unless SaveForm.allowed?(team, socket.assigns.current_user), do: raise(Web.Status.NotFound)

    socket =
      socket
      |> assign(
        page_title: "New form",
        team: team,
        errors: %{},
        name: "",
        for: "",
        max_for: @max_for
      )
      |> assign(
        ai?: AskAI.check(team, socket.assigns.current_user, DateTime.utc_now(), :form) == :ok
      )
      |> allow_upload(:page, accept: ~w(.pdf), max_entries: 1, max_file_size: 10_000_000)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={FormOwner.settings_path(@team)} />
      <:item label="Forms" path={FormOwner.forms_path(@team)} />
      <:item label="New form" />
    </.breadcrumbs>
    <h1 class="title">New form</h1>
    <p :if={!@ai?} class="lead measure">
      Give SAR Duty the agency's PDF. The form starts off, and stays off until it's written.
    </p>
    <p :if={@ai?} class="lead measure">
      Give SAR Duty the agency's PDF, and AI writes the form from it. The form starts off,
      and stays off until you turn it on.
    </p>

    <.form for={%{}} id="form-start" phx-change="validate" phx-submit="save" class="measure">
      <.input
        id="form-start-name"
        name="name"
        value={@name}
        label="Name"
        errors={List.wrap(@errors[:name])}
      />

      <.file_drop
        id="form-start-page"
        upload={@uploads.page}
        label="The agency's PDF"
        kinds="a PDF"
        errors={List.wrap(@errors[:page])}
      >
        The blank form, as the agency gives it. A scan has no text to read.
      </.file_drop>

      <.input
        :if={@ai?}
        id="form-start-for"
        name="for"
        type="textarea"
        rows="3"
        value={@for}
        label="What it's for (optional)"
        maxlength={@max_for}
      >
        When it's filled in and who signs it.
      </.input>

      <.form_actions>
        <.button id="form-start-save" variant={:success} phx-disable-with="Reading the PDF…">
          {if @ai?, do: "Write form", else: "Add form"}
        </.button>
        <.button navigate={FormOwner.forms_path(@team)}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"name" => name} = params, socket),
    do: {:noreply, assign(socket, name: name, for: params["for"] || socket.assigns.for)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :page, ref)}

  def handle_event("save", params, socket) do
    %{team: team, current_user: user} = socket.assigns
    name = params["name"]
    socket = assign(socket, name: name, for: params["for"] || "")

    case SaveForm.start(team, name, page(socket), user) do
      {:ok, form} when socket.assigns.ai? ->
        socket =
          socket
          |> put_flash(:info, "#{form.name} added. AI is writing it.")
          |> put_flash(:ai_ask, first_ask(params["for"]))
          |> push_navigate(to: FormOwner.change_path(team, form))

        {:noreply, socket}

      {:ok, form} ->
        socket =
          socket
          |> put_flash(:info, "#{form.name} added.")
          |> push_navigate(to: FormOwner.form_path(team, form))

        {:noreply, socket}

      {:error, field, message} ->
        {:noreply, assign(socket, errors: %{field => message})}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer add this team's forms.")}
    end
  end

  # What it's for, or "Write this form." without it.
  defp first_ask(for_text) do
    case String.trim(for_text || "") do
      "" -> "Write this form."
      text -> String.slice(text, 0, @max_for)
    end
  end

  defp page(socket) do
    case consume_uploaded_entries(socket, :page, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> nil
    end
  end
end
