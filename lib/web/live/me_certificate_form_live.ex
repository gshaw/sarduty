defmodule Web.MeCertificateFormLive do
  use Web, {:live_view_app_layout, access: :member}

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Certificate
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.SaveCertificate
  alias App.Repo
  alias Service.Format
  alias Web.CertificateText

  # A member sends a certificate for a qualification (#493), or changes one while it
  # waits: /teams/:subdomain/me/certificates/new, with `?qualification=<id>` to start on
  # one, and /me/certificates/:id/edit. The expiry fills in from the qualification.
  def mount(params, _session, socket) do
    member = socket.assigns.current_member
    if !Team.certificates?(member.team), do: raise(Web.Status.NotFound)
    certificate = if id = params["id"], do: Certificate.find_for_member!(member, id)
    if certificate && !Certificate.member_can_change?(certificate), do: raise(Web.Status.NotFound)

    qualifications = Qualification.get_all(member.team_id)
    latest = latest_awards(member)

    socket
    |> assign(member: member, certificate: certificate, latest: latest)
    |> assign(qualifications: qualifications)
    |> assign(options: options(qualifications, latest))
    |> assign(page_title: if(certificate, do: "Change certificate", else: "Add a certificate"))
    |> assign(service: D4H.service_name(member.team), filled: nil, fill_key: nil, fill: nil)
    |> allow_upload(:certificate,
      accept: ~w(image/* application/pdf),
      max_entries: 1,
      max_file_size: Service.CertificateFile.max_bytes()
    )
    |> start(certificate, params["qualification"], qualifications)
    |> then(&{:ok, &1})
  end

  defp start(socket, nil, qualification_id, qualifications) do
    id = Enum.find_value(qualifications, &(to_string(&1.id) == qualification_id && &1.id))
    assign_form(socket, %{"qualification_id" => id && to_string(id)}, nil)
  end

  defp start(socket, certificate, _qualification_id, _qualifications) do
    params = %{
      "qualification_id" => to_string(certificate.qualification_id),
      "starts_on" => Date.to_iso8601(certificate.starts_on),
      "ends_on" => certificate.ends_on && Date.to_iso8601(certificate.ends_on)
    }

    socket
    |> assign(
      filled: params["ends_on"],
      fill_key: {certificate.qualification_id, certificate.starts_on}
    )
    |> assign_form(params, nil)
  end

  # The member's latest award of each qualification, for the order of the list and the
  # expiry it fills in.
  defp latest_awards(member) do
    MemberQualificationAward
    |> where(member_id: ^member.id)
    |> order_by([a], asc_nulls_first: a.starts_at, asc: a.id)
    |> Repo.all()
    |> Map.new(&{&1.qualification_id, &1})
  end

  # The member's own first, then every other the team has.
  defp options(qualifications, latest) do
    own_ids = latest |> Map.keys() |> MapSet.new()
    CertificateText.qualification_options(qualifications, own_ids, "Your qualifications")
  end

  # The expiry fills in when the qualification or the start changes, unless the member
  # typed their own. Blank stays blank: it never expires.
  defp assign_form(socket, params, action) do
    {params, socket} = fill_expiry(socket, params)

    changeset =
      (socket.assigns.certificate || %Certificate{})
      |> Certificate.build_changeset(params, Enum.map(socket.assigns.qualifications, & &1.id))
      |> Map.put(:action, action)

    assign(socket, form: to_form(changeset, as: "certificate"))
  end

  defp fill_expiry(socket, params) do
    %{filled: filled, fill_key: fill_key, latest: latest} = socket.assigns
    qualification = find_qualification(socket, params["qualification_id"])
    starts_on = parse_date(params["starts_on"])
    key = {qualification && qualification.id, starts_on}
    award = qualification && latest[qualification.id]

    cond do
      key == fill_key ->
        {params, socket}

      params["ends_on"] not in [nil, "", filled] ->
        {params, assign(socket, fill_key: key)}

      default = Certificate.default_ends_on(starts_on, qualification, award) ->
        {ends_on, months} = default
        value = Date.to_iso8601(ends_on)

        {Map.put(params, "ends_on", value),
         assign(socket, fill_key: key, filled: value, fill: {qualification, months})}

      true ->
        {Map.put(params, "ends_on", ""), assign(socket, fill_key: key, filled: nil, fill: nil)}
    end
  end

  # Whether the expiry is still the one filled in, for its hint.
  defp filled?(form, filled), do: filled != nil and date_text(form[:ends_on].value) == filled

  defp date_text(%Date{} = date), do: Date.to_iso8601(date)
  defp date_text(text), do: text

  defp find_qualification(socket, id),
    do: Enum.find(socket.assigns.qualifications, &(to_string(&1.id) == id))

  defp parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp parse_date(_text), do: nil

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@member.team}/me"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p class="lead measure">
      A team admin looks at it, then records the award in {@service}.
    </p>

    <.form
      for={@form}
      id="certificate-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <.error_summary form={@form} />
      <.input
        field={@form[:qualification_id]}
        type="combobox"
        label="Qualification"
        prompt="Select a qualification"
        options={@options}
      />
      <.input field={@form[:starts_on]} type="date" label="Start">
        The date on the certificate.
      </.input>
      <.input field={@form[:ends_on]} type="date" label="Expiry (optional)">
        <%= if @fill && filled?(@form, @filled) do %>
          Filled in: {elem(@fill, 0).title} lasts {Format.months(elem(@fill, 1))}. Leave it blank if it never expires.
        <% else %>
          Leave it blank if it never expires.
        <% end %>
      </.input>

      <div id="certificate-file" class="mb-6">
        <.label for={@uploads.certificate.ref}>Certificate</.label>
        <.hint>
          A photo or a PDF, up to {Format.file_size(Service.CertificateFile.max_bytes())}. On a phone you can take the photo now.
        </.hint>
        <.live_file_input upload={@uploads.certificate} class="my-2" />
        <.error :for={error <- upload_errors(@uploads.certificate)}>{upload_error(error)}</.error>
        <.error :for={error <- @form[:file_name].errors}>{translate_error(error)}</.error>
        <div
          :for={entry <- @uploads.certificate.entries}
          id={"certificate-entry-#{entry.ref}"}
          class="media mt-2"
        >
          <.live_img_preview :if={image?(entry)} entry={entry} class="photo-sm" />
          <div>
            <span class="block">{entry.client_name}</span>
            <span class="hint block">{Format.file_size(entry.client_size)}</span>
            <.error :for={error <- upload_errors(@uploads.certificate, entry)}>
              {upload_error(error)}
            </.error>
            <.a
              href="#"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              aria-label={"Remove #{entry.client_name}"}
            >Remove</.a>
          </div>
        </div>
        <p
          :if={@certificate && @uploads.certificate.entries == []}
          id="certificate-sent-file"
          class="hint"
        >
          Sent: <.a
            href={~p"/teams/#{@member.team}/me/certificates/#{@certificate.id}/file"}
            target="_blank"
          >{@certificate.file_name}</.a>, {Format.file_size(@certificate.file_size)}. Choose a file to send another.
        </p>
      </div>

      <.form_actions>
        <.button id="certificate-save" variant={:success} phx-disable-with="Sending…">
          {if @certificate, do: "Save certificate", else: "Send certificate"}
        </.button>
        <.button navigate={~p"/teams/#{@member.team}/me"}>Cancel</.button>
        <:trailing :if={@certificate}>
          <.button
            id="certificate-delete"
            type="button"
            variant={:danger}
            phx-click="delete"
            data-confirm={"Delete your #{@certificate.qualification && @certificate.qualification.title} certificate?"}
          >
            Delete certificate
          </.button>
        </:trailing>
      </.form_actions>
    </.form>
    """
  end

  defp image?(entry), do: String.starts_with?(entry.client_type, "image/")

  defp upload_error(:too_large),
    do:
      "That file is too large. Use one under #{Format.file_size(Service.CertificateFile.max_bytes())}."

  defp upload_error(:not_accepted), do: "Choose a photo or a PDF."
  defp upload_error(:too_many_files), do: "Choose one file."
  defp upload_error(_error), do: "That file did not upload. Try again."

  def handle_event("validate", %{"certificate" => params}, socket),
    do: {:noreply, assign_form(socket, params, :validate)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :certificate, ref)}

  def handle_event("save", %{"certificate" => params}, socket) do
    %{member: member, certificate: certificate} = socket.assigns
    socket = assign_form(socket, params, :insert)

    # The file is read only once the rest is right, so a mistake doesn't lose it.
    if socket.assigns.form.source.valid?,
      do: save(socket, member, certificate, socket.assigns.form.source.params),
      else: {:noreply, socket}
  end

  def handle_event("delete", _params, socket) do
    %{member: member, certificate: certificate} = socket.assigns

    case SaveCertificate.delete_own(member, certificate) do
      :ok ->
        socket
        |> put_flash(:info, "Deleted your certificate.")
        |> push_navigate(to: ~p"/teams/#{member.team}/me")
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}
    end
  end

  defp save(socket, member, certificate, params) do
    file =
      socket
      |> consume_uploaded_entries(:certificate, fn %{path: path}, entry ->
        {:ok, %{bytes: File.read!(path), file_name: entry.client_name}}
      end)
      |> List.first()

    result =
      if certificate,
        do: SaveCertificate.change_own(member, certificate, params, file),
        else: SaveCertificate.send(member, params, file)

    case result do
      {:ok, _saved} ->
        socket
        |> put_flash(
          :info,
          if(certificate,
            do: "Saved your certificate.",
            else: "Sent your certificate. A team admin adds it to #{socket.assigns.service}."
          )
        )
        |> push_navigate(to: ~p"/teams/#{member.team}/me")
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "certificate"))}
    end
  end

  # A team admin decided the certificate after this page opened.
  defp decided(socket) do
    socket
    |> put_flash(
      :error,
      "This certificate cannot change. A team admin has decided it since you opened it."
    )
    |> push_navigate(to: ~p"/teams/#{socket.assigns.member.team}/me")
  end
end
