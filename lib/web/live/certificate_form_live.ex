defmodule Web.CertificateFormLive do
  use Web,
      {:live_view_app_layout,
       access: :team,
       view_events: ["validate", "cancel-upload"],
       member_events: ["save", "delete"]}

  import Web.Components.FileDrop

  alias App.Model.Certificate
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.SaveCertificate
  alias Service.Format
  alias Web.CertificateExpiry
  alias Web.CertificateText

  # A member sends a certificate (#493), or changes one while it waits:
  # /teams/:subdomain/certificates/new, with `?qualification=<id>` to start on one, and
  # /certificates/:id/edit. The same URLs for a team admin who is a member, from
  # Certificates (#645); anyone else is not found. The file comes first; the qualification
  # is optional, since a team admin picks it from the certificate when the member is not
  # sure. The expiry fills in from the qualification (Web.CertificateExpiry).
  def mount(params, _session, socket) do
    member = socket.assigns.current_member
    if !member, do: raise(Web.Status.NotFound)
    if !Team.certificates?(member.team), do: raise(Web.Status.NotFound)
    certificate = if id = params["id"], do: Certificate.find_for_member!(member, id)
    if certificate && !Certificate.member_can_change?(certificate), do: raise(Web.Status.NotFound)

    qualifications = Qualification.get_all(member.team_id)
    latest = MemberQualificationAward.latest_by_qualification(member.id)

    socket
    |> assign(member: member, certificate: certificate, latest: latest)
    |> assign(qualifications: qualifications)
    |> assign(options: options(qualifications, latest))
    |> assign(page_title: if(certificate, do: "Change certificate", else: "Add a certificate"))
    |> assign(expiry: CertificateExpiry.new(certificate))
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
      "qualification_id" =>
        certificate.qualification_id && to_string(certificate.qualification_id),
      "starts_on" => Date.to_iso8601(certificate.starts_on),
      "ends_on" => certificate.ends_on && Date.to_iso8601(certificate.ends_on),
      "note" => certificate.note
    }

    assign_form(socket, params, nil)
  end

  # The member's own first, then every other the team has.
  defp options(qualifications, latest) do
    own_ids = latest |> Map.keys() |> MapSet.new()
    CertificateText.qualification_options(qualifications, own_ids, "Your qualifications")
  end

  defp assign_form(socket, params, action) do
    %{expiry: expiry, qualifications: qualifications, latest: latest} = socket.assigns
    {params, expiry} = CertificateExpiry.fill(expiry, params, qualifications, latest)

    changeset =
      (socket.assigns.certificate || %Certificate{})
      |> Certificate.member_changeset(params, Enum.map(qualifications, & &1.id))
      |> Map.put(:action, action)

    assign(socket, expiry: expiry, form: to_form(changeset, as: "certificate"))
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@member.team}/me"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>
    <p class="lead measure">
      A team admin looks at it, then records the award.
    </p>

    <.form
      for={@form}
      id="certificate-form"
      class="measure"
      phx-change="validate"
      phx-submit="save"
    >
      <.error_summary form={@form} />
      <%!-- The field's id, so the error summary's link lands on the file. --%>
      <.file_drop
        id={@form[:file_name].id}
        upload={@uploads.certificate}
        label="Certificate"
        kinds="a photo or a PDF"
        errors={Enum.map(@form[:file_name].errors, &translate_error/1)}
      >
        A photo or a PDF, up to {Format.file_size(Service.CertificateFile.max_bytes())}.
        <:current :if={@certificate && @uploads.certificate.entries == []}>
          <p id="certificate-sent-file" class="hint mb-0">
            Sent: <.a
              href={~p"/teams/#{@member.team}/certificates/#{@certificate.id}/file"}
              target="_blank"
            >{@certificate.file_name}</.a>, {Format.file_size(@certificate.file_size)}. Select a file to send another.
          </p>
        </:current>
      </.file_drop>

      <.input
        field={@form[:qualification_id]}
        type="combobox"
        label="Qualification (optional)"
        prompt="Select a qualification"
        options={@options}
      >
        Not sure? Leave it blank. A team admin reads it from the certificate.
      </.input>
      <.input field={@form[:starts_on]} type="date" label="Start">
        The date on the certificate.
      </.input>
      <.input field={@form[:ends_on]} type="date" label="Expiry (optional)">
        <%= if fill = CertificateExpiry.hint(@expiry, @form) do %>
          Filled in: {elem(fill, 0).title} lasts {Format.months(elem(fill, 1))}. Leave it blank if it never expires.
        <% else %>
          Leave it blank if it never expires.
        <% end %>
      </.input>
      <.input
        field={@form[:note]}
        type="textarea"
        rows="3"
        label="Note for a team admin (optional)"
      >
        For example, which course it was.
      </.input>

      <.form_actions>
        <.button
          id="certificate-save"
          variant={:success}
          phx-disable-with="Sending…"
          disabled={@viewing_as != nil}
        >
          {if @certificate, do: "Save certificate", else: "Send certificate"}
        </.button>
        <.button navigate={~p"/teams/#{@member.team}/me"}>Cancel</.button>
        <:trailing :if={@certificate}>
          <.button
            id="certificate-delete"
            type="button"
            variant={:danger}
            disabled={@viewing_as != nil}
            phx-click="delete"
            data-confirm={CertificateText.delete_question(@certificate)}
          >
            Delete certificate
          </.button>
        </:trailing>
      </.form_actions>
    </.form>
    """
  end

  def handle_event("validate", %{"certificate" => params}, socket),
    do: {:noreply, assign_form(socket, params, :validate)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :certificate, ref)}

  def handle_event("save", %{"certificate" => params}, socket) do
    %{member: member, certificate: certificate} = socket.assigns
    socket = assign_form(socket, params, :insert)
    changeset = socket.assigns.form.source

    # The file is read only once the rest is right, so a mistake doesn't lose it. A missing
    # one is checked now, so every mistake shows at once.
    cond do
      !certificate and socket.assigns.uploads.certificate.entries == [] ->
        form = changeset |> SaveCertificate.missing_file() |> to_form(as: "certificate")
        {:noreply, assign(socket, form: form)}

      changeset.valid? ->
        save(socket, member, certificate, changeset.params)

      true ->
        {:noreply, socket}
    end
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
            else: "Sent your certificate. A team admin looks at it next."
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
