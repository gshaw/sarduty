defmodule Web.FormStartLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop

  alias App.Operation.SaveForm
  alias Web.FormOwner

  # New form on a team's Forms tab (#1083): its name and the agency's PDF. It saves off,
  # with no text, and stays off until it's written. An organization's forms are uploaded
  # instead (Web.FormUploadLive).
  def mount(_params, _session, socket) do
    team = FormOwner.get(socket.assigns)
    unless SaveForm.allowed?(team, socket.assigns.current_user), do: raise(Web.Status.NotFound)

    socket =
      socket
      |> assign(page_title: "New form", team: team, errors: %{}, name: "")
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
    <p class="lead measure">
      Give SAR Duty the agency's PDF. The form starts off, and stays off until it's written.
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

      <.form_actions>
        <.button variant={:success} phx-disable-with="Reading the PDF…">Add form</.button>
        <.button navigate={FormOwner.forms_path(@team)}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"name" => name}, socket),
    do: {:noreply, assign(socket, name: name)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :page, ref)}

  def handle_event("save", params, socket) do
    %{team: team, current_user: user} = socket.assigns
    name = params["name"]
    socket = assign(socket, name: name)

    case SaveForm.start(team, name, page(socket), user) do
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

  defp page(socket) do
    case consume_uploaded_entries(socket, :page, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> nil
    end
  end
end
