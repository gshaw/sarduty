defmodule Web.Org.FormUploadLive do
  use Web, :live_view_app_layout

  import Web.Components.FileDrop

  alias App.Model.Form
  alias App.Operation.SaveForm

  # Upload form and Replace form (#950), for SAR Duty admins: the form's text and its page
  # PDF, prepared on a Mac. There's no editor here. Saving checks the text on every team
  # in the organization and on Coast Range SAR (App.Operation.SaveForm).
  def mount(params, _session, socket) do
    unless socket.assigns.current_user.is_admin, do: raise(Web.Status.NotFound)
    organization = socket.assigns.current_organization

    form =
      case socket.assigns.live_action do
        :new -> nil
        :edit -> Form.get(organization, params["id"]) || raise(Web.Status.NotFound)
      end

    socket =
      socket
      |> assign(
        page_title: if(form, do: "#{form.name} · Replace", else: "Upload form"),
        form: form,
        errors: %{},
        # Files from a save that failed, so fixing one doesn't mean choosing both again.
        kept: %{}
      )
      |> allow_upload(:text, accept: ~w(.txt), max_entries: 1, max_file_size: 200_000)
      |> allow_upload(:page, accept: ~w(.pdf), max_entries: 1, max_file_size: 10_000_000)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Forms" path={~p"/orgs/#{@current_organization}/forms"} />
      <:item :if={@form} label={@form.name} path={~p"/orgs/#{@current_organization}/forms/#{@form}"} />
      <:item label={if @form, do: "Replace", else: "Upload form"} />
    </.breadcrumbs>
    <h1 class="title">{if @form, do: "Replace #{@form.name}", else: "Upload form"}</h1>
    <p class="lead measure">
      Saving checks the text on every team in {@current_organization.short_name} and on Coast
      Range SAR. Every expect must hold.
    </p>

    <.form
      for={%{}}
      as={:upload}
      id="form-upload"
      phx-change="validate"
      phx-submit="save"
      class="measure"
    >
      <.file_drop
        id="form-text-file"
        upload={@uploads.text}
        label={if @form, do: "Text (optional)", else: "Text"}
        kinds="a text file"
        errors={List.wrap(@errors[:text])}
      >
        The form's .txt file, starting with form and its name.
        <span :if={@form}>Leave it empty to keep its text.</span>
        <:current :if={@kept[:text]}>
          <span id="form-text-kept" class="hint">The text from your last try. Choose another to change it.</span>
        </:current>
      </.file_drop>

      <.file_drop
        id="form-page-file"
        upload={@uploads.page}
        label={if @form, do: "Page (optional)", else: "Page"}
        kinds="a PDF"
        errors={List.wrap(@errors[:page])}
      >
        The agency's PDF the values print on, when the text says page.
        <span :if={@form}>Leave it empty to keep its page.</span>
        <:current :if={@kept[:page]}>
          <span id="form-page-kept" class="hint">The page from your last try. Choose another to change it.</span>
        </:current>
      </.file_drop>

      <.form_actions>
        <.button variant={:success} phx-disable-with="Checking…">
          {if @form, do: "Replace form", else: "Upload form"}
        </.button>
        <.button navigate={cancel_path(@current_organization, @form)}>Cancel</.button>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    name = if ref == socket.assigns.uploads.text.ref, do: :text, else: :page
    {:noreply, cancel_upload(socket, name, ref)}
  end

  def handle_event("save", _params, socket) do
    %{form: form, kept: kept} = socket.assigns
    kept = %{text: upload(socket, :text, kept), page: upload(socket, :page, kept)}
    socket = assign(socket, kept: kept)

    case kept.text || (form && form.text) do
      nil -> {:noreply, assign(socket, errors: %{text: "Upload the form's text, a .txt file."})}
      text -> save(socket, text, kept.page)
    end
  end

  defp save(socket, text, page) do
    %{current_organization: organization, current_user: user, form: form} = socket.assigns

    case SaveForm.call(organization, form, text, page, user) do
      {:ok, saved} ->
        socket =
          socket
          |> put_flash(:info, saved_message(form, saved))
          |> push_navigate(to: ~p"/orgs/#{organization}/forms/#{saved}")

        {:noreply, socket}

      {:error, field, message} ->
        {:noreply, assign(socket, errors: %{field => message})}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "Only a SAR Duty site admin uploads a form.")}
    end
  end

  defp cancel_path(organization, nil), do: ~p"/orgs/#{organization}/forms"
  defp cancel_path(organization, form), do: ~p"/orgs/#{organization}/forms/#{form}"

  defp saved_message(nil, saved), do: "#{saved.name} uploaded."
  defp saved_message(_form, saved), do: "#{saved.name} replaced. It's version #{saved.version}."

  # A file just chosen, or the one kept from the last try.
  defp upload(socket, name, kept) do
    case consume_uploaded_entries(socket, name, fn %{path: path}, _entry ->
           {:ok, File.read!(path)}
         end) do
      [bytes] -> bytes
      [] -> kept[name]
    end
  end
end
