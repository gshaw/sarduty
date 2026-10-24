defmodule Web.CertificateLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Adapter.D4H
  alias App.Model.Certificate
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.AcceptCertificate
  alias App.Operation.SaveCertificate
  alias App.Repo
  alias Service.Format
  alias Web.CertificateText

  # One certificate a member sent (#493), /teams/:subdomain/certificates/:id: the file
  # beside its dates. A team admin can change the qualification and dates, then accept it,
  # which adds the award to D4H with the file, or decline it with a reason the member
  # sees.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !Team.certificates?(team), do: raise(Web.Status.NotFound)

    socket
    |> assign(service: D4H.service_name(team), now: DateTime.utc_now())
    |> assign(qualifications: Qualification.get_all(team.id))
    |> load(id)
    |> assign_decline_form(%{})
    |> then(&{:ok, &1})
  end

  defp load(socket, id) do
    certificate = Certificate.find!(socket.assigns.current_team, id)

    socket
    |> assign(certificate: certificate, latest: Certificate.latest_award(certificate))
    |> assign(page_title: "#{CertificateText.title(certificate)}, #{certificate.member.name}")
    |> assign(options: options(socket.assigns.qualifications, certificate))
    |> assign(accepted_award: accepted_award(certificate))
    |> assign_form(Certificate.build_changeset(certificate, %{}, []))
  end

  defp options(qualifications, certificate) do
    own_ids =
      MemberQualificationAward
      |> where(member_id: ^certificate.member_id)
      |> select([a], a.qualification_id)
      |> Repo.all()
      |> MapSet.new()

    CertificateText.qualification_options(qualifications, own_ids, "Their qualifications")
  end

  # Once accepted, the file is D4H's, opened through the award (#434).
  defp accepted_award(%Certificate{status: :accepted, d4h_award_id: award_id} = certificate),
    do: MemberQualificationAward.get_by(member_id: certificate.member_id, d4h_award_id: award_id)

  defp accepted_award(_certificate), do: nil

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: "certificate"))

  defp assign_decline_form(socket, params, errors \\ []),
    do: assign(socket, :decline_form, to_form(params, as: "decline", errors: errors))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Certificates" path={~p"/teams/#{@current_team}/certificates"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">{CertificateText.title(@certificate)}</h1>

    <.banner
      :if={@certificate.status == :waiting and Certificate.dates_locked?(@certificate)}
      id="certificate-not-uploaded"
      kind={:warning}
      title={"The certificate is not in #{@service} yet"}
    >
      <p>
        The award is in {@service}, but its certificate did not upload. Send again to upload it.
      </p>
      <p :if={error = upload_error(@certificate)} class="hint">{error}</p>
    </.banner>

    <div class="content-wrapper">
      <div class="content-2/3">
        <.certificate_file
          certificate={@certificate}
          src={file_path(@current_team, @certificate, @accepted_award)}
        />
      </div>
      <aside class="content-1/3">
        <dl id="certificate-details" class="mb-6">
          <dt>Member</dt>
          <dd>
            <.a navigate={~p"/teams/#{@current_team}/members/#{@certificate.member_id}"}>{@certificate.member.name}</.a>
          </dd>
          <dt>Sent</dt>
          <dd>{Format.datetime_short(@certificate.inserted_at, @current_team.timezone)}</dd>
          <dt :if={@certificate.status == :waiting}>In {@service} now</dt>
          <dd :if={@certificate.status == :waiting} id="certificate-latest">
            <.latest award={@latest} now={@now} timezone={@current_team.timezone} />
          </dd>
          <dt :if={@certificate.status != :waiting}>Dates</dt>
          <dd :if={@certificate.status != :waiting}>{CertificateText.dates(@certificate)}</dd>
          <dt>Status</dt>
          <dd id="certificate-status">
            <.badge :if={@certificate.status == :waiting}>Waiting</.badge>
            <.badge :if={@certificate.status == :declined} kind={:warning}>Declined</.badge>
            <span :if={@certificate.status == :accepted}>Accepted</span>
            <span :if={@certificate.decided_at} class="hint">
              {Format.datetime_short(@certificate.decided_at, @current_team.timezone)}{if @certificate.decided_by_user,
                do: ", #{@certificate.decided_by_user.email}"}
            </span>
          </dd>
          <div :if={@certificate.status == :declined}>
            <dt>Why not</dt>
            <dd id="certificate-decline-reason">{@certificate.decline_reason}</dd>
          </div>
        </dl>

        <.form
          :if={@certificate.status == :waiting}
          for={@form}
          id="accept-form"
          phx-submit="accept"
        >
          <.error_summary form={@form} />
          <%= if Certificate.dates_locked?(@certificate) do %>
            <p class="hint">{CertificateText.dates(@certificate)}</p>
          <% else %>
            <.input
              field={@form[:qualification_id]}
              type="combobox"
              label="Qualification"
              prompt="Select a qualification"
              options={@options}
            />
            <.input field={@form[:starts_on]} type="date" label="Start" />
            <.input field={@form[:ends_on]} type="date" label="Expiry (optional)" />
            <.warning_text class="mb-4">
              Once it is in {@service}, only {@service} can change or remove the award.
            </.warning_text>
          <% end %>
          <.form_actions>
            <.button
              id="certificate-accept"
              variant={:success}
              phx-disable-with={"Sending to #{@service}…"}
            >
              {if Certificate.dates_locked?(@certificate),
                do: "Send again",
                else: "Accept certificate"}
            </.button>
          </.form_actions>
        </.form>

        <section :if={@certificate.status == :waiting} id="certificate-decline" class="mt-8">
          <h2 class="subheading">Decline</h2>
          <.warning_text :if={Certificate.dates_locked?(@certificate)} class="mb-4">
            The award stays in {@service}. Only {@service} can remove it.
          </.warning_text>
          <.form for={@decline_form} id="decline-form" phx-submit="decline">
            <.input field={@decline_form[:reason]} type="textarea" rows="3" label="Why not">
              {first_name(@certificate.member.name)} sees this on Your membership.
            </.input>
            <.form_actions>
              <.button id="certificate-decline-button" variant={:danger}>
                Decline certificate
              </.button>
            </.form_actions>
          </.form>
        </section>
      </aside>
    </div>
    """
  end

  attr :certificate, :map, required: true
  attr :src, :string, default: nil

  # A photo as an image, a PDF in the browser's own viewer. The frame has no `sandbox`
  # attribute: it would block Chrome's viewer, and the file's own header sandboxes it.
  defp certificate_file(%{src: nil} = assigns) do
    ~H"""
    <p id="certificate-file-gone" class="hint">
      SAR Duty deleted its copy of the file when the certificate was declined.
    </p>
    """
  end

  defp certificate_file(assigns) do
    ~H"""
    <div id="certificate-file">
      <img
        :if={@certificate.content_type != "application/pdf"}
        id="certificate-image"
        src={@src}
        alt={"#{@certificate.member.name}'s certificate"}
        class="w-full border border-border-subtle"
      />
      <iframe
        :if={@certificate.content_type == "application/pdf"}
        id="certificate-pdf"
        src={@src}
        title={"#{@certificate.member.name}'s certificate"}
        class="w-full h-screen border border-border-subtle"
      ></iframe>
      <p class="action mt-2">
        <.a id="certificate-open" href={@src} target="_blank">Open certificate</.a>
        <span class="hint">
          {@certificate.file_name}, {Format.file_size(@certificate.file_size)}
        </span>
      </p>
    </div>
    """
  end

  attr :award, :map, default: nil
  attr :now, :any, required: true
  attr :timezone, :string, required: true

  defp latest(%{award: nil} = assigns), do: ~H"None"

  defp latest(assigns) do
    ~H"""
    {award_dates(@award, @timezone)}
    <span :if={@award.ends_at} class="hint block">{expiry(@award.ends_at, @now)}</span>
    """
  end

  defp award_dates(%{starts_at: starts_at, ends_at: nil}, timezone),
    do: "From #{Format.date_short(starts_at, timezone)}"

  defp award_dates(%{starts_at: starts_at, ends_at: ends_at}, timezone),
    do: "#{Format.date_short(starts_at, timezone)} to #{Format.date_short(ends_at, timezone)}"

  defp expiry(ends_at, now) do
    if DateTime.after?(ends_at, now),
      do: "Expires in #{Format.days(Service.Convert.days_until(ends_at, now))}",
      else: "Expired"
  end

  defp file_path(team, %Certificate{status: :waiting} = certificate, _award),
    do: ~p"/teams/#{team}/certificates/#{certificate.id}/file"

  defp file_path(
         team,
         %Certificate{status: :accepted} = certificate,
         %{d4h_document_id: id} = award
       )
       when is_integer(id),
       do: ~p"/teams/#{team}/members/#{certificate.member_id}/certificates/#{award.id}"

  defp file_path(_team, _certificate, _award), do: nil

  defp upload_error(%Certificate{change_set: %{rows: rows}}) do
    Enum.find_value(rows, &(&1.action == :attach_award_document and &1.error))
  end

  defp upload_error(_certificate), do: nil

  defp first_name(name), do: name |> String.split(" ", parts: 2) |> hd()

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, certificate: certificate} = socket.assigns
    values = params["certificate"] || %{}

    case AcceptCertificate.call(team, certificate, values, user, DateTime.utc_now()) do
      {:ok, accepted} ->
        {:noreply, accepted(socket, Repo.preload(accepted, [:member, :qualification]))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, text} ->
        socket
        |> put_flash(:error, text)
        |> load(certificate.id)
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("decline", %{"decline" => %{"reason" => reason}}, socket) do
    %{current_team: team, current_user: user, certificate: certificate} = socket.assigns

    case SaveCertificate.decline(team, certificate, reason, user, DateTime.utc_now()) do
      {:ok, _declined} ->
        socket
        |> put_flash(
          :info,
          "Declined #{CertificateText.title(certificate)} for #{certificate.member.name}."
        )
        |> push_navigate(to: ~p"/teams/#{team}/certificates")
        |> then(&{:noreply, &1})

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, changeset} ->
        errors = for {:decline_reason, error} <- changeset.errors, do: {:reason, error}
        {:noreply, assign_decline_form(socket, %{"reason" => reason}, errors)}
    end
  end

  defp accepted(socket, certificate) do
    socket
    |> put_flash(
      :info,
      "Accepted #{CertificateText.title(certificate)} for #{certificate.member.name}. It is in #{socket.assigns.service}."
    )
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/certificates")
  end

  defp decided(socket) do
    socket
    |> put_flash(:error, "Another team admin has decided this certificate.")
    |> load(socket.assigns.certificate.id)
  end
end
