defmodule Web.CertificateLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Certificate
  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.AcceptCertificate
  alias App.Operation.FindCertificateAward
  alias App.Operation.SaveCertificate
  alias App.Repo
  alias Service.Format
  alias Web.CertificateExpiry
  alias Web.CertificateText
  alias Web.QualificationText

  # One certificate a member sent (#493), /teams/:subdomain/certificates/:id: the file
  # beside its dates. A team admin picks or changes the qualification and dates, selects
  # the box that says they checked them against the certificate, then accepts it, which
  # adds the award to D4H with the file, or declines it with a reason the member sees.
  # Dates that look wrong get a warning, never an error. When D4H already has the award,
  # read as the page opens, Attach certificate puts the file on it instead.
  def mount(%{"id" => id}, _session, socket) do
    team = socket.assigns.current_team
    if !Team.certificates?(team), do: raise(Web.Status.NotFound)

    socket
    |> assign(now: DateTime.utc_now(), checked_key: nil)
    |> assign(qualifications: Qualification.get_all(team.id))
    |> load(id)
    |> assign_decline_form(%{})
    |> then(&{:ok, &1})
  end

  defp load(socket, id) do
    certificate = Certificate.find!(socket.assigns.current_team, id)
    latest = MemberQualificationAward.latest_by_qualification(certificate.member_id)
    own_ids = latest |> Map.keys() |> MapSet.new()

    socket
    |> assign(certificate: certificate, latest: latest)
    |> assign(page_title: page_title(certificate))
    |> assign(
      options:
        CertificateText.qualification_options(
          socket.assigns.qualifications,
          own_ids,
          "Their qualifications"
        )
    )
    |> assign(accepted_award: accepted_award(certificate))
    |> assign(existing: existing(socket, certificate))
    |> assign(expiry: CertificateExpiry.new(certificate), checked_key: nil)
    |> assign_form(start_params(certificate), nil)
  end

  defp page_title(%Certificate{qualification: %{title: title}, member: member}),
    do: "#{title}, #{member.name}"

  defp page_title(%Certificate{member: member}), do: "Certificate from #{member.name}"

  defp start_params(certificate) do
    %{
      "qualification_id" =>
        certificate.qualification_id && to_string(certificate.qualification_id),
      "starts_on" => Date.to_iso8601(certificate.starts_on),
      "ends_on" => certificate.ends_on && Date.to_iso8601(certificate.ends_on)
    }
  end

  # D4H's award of the same qualification from the same day, read once the page is live.
  # A read that fails shows nothing: accepting reads D4H again before it writes.
  defp existing(socket, %Certificate{status: :waiting} = certificate) do
    with true <- connected?(socket) and not Certificate.dates_locked?(certificate),
         {:ok, award} <- FindCertificateAward.call(socket.assigns.current_team, certificate) do
      award
    else
      _none -> nil
    end
  end

  defp existing(_socket, _certificate), do: nil

  # Once accepted, the file is D4H's, opened through the award (#434).
  defp accepted_award(%Certificate{status: :accepted, d4h_award_id: award_id} = certificate),
    do: MemberQualificationAward.get_by(member_id: certificate.member_id, d4h_award_id: award_id)

  defp accepted_award(_certificate), do: nil

  # The expiry fills in as on the member's form. The box says it was checked against the
  # values it names, so it clears when they change after it was selected.
  defp assign_form(socket, params, action) do
    %{expiry: expiry, qualifications: qualifications, latest: latest} = socket.assigns
    {params, expiry} = CertificateExpiry.fill(expiry, params, qualifications, latest)
    {params, checked_key} = check_box(params, socket.assigns.checked_key)

    changeset =
      socket.assigns.certificate
      |> Certificate.accept_changeset(params, Enum.map(qualifications, & &1.id))
      |> Map.put(:action, action)

    socket
    |> assign(expiry: expiry, checked_key: checked_key)
    |> assign_changeset(changeset)
  end

  defp check_box(%{"confirmed" => "true"} = params, checked_key) do
    key = Map.take(params, ["qualification_id", "starts_on", "ends_on"])

    if checked_key in [nil, key],
      do: {params, key},
      else: {Map.put(params, "confirmed", "false"), nil}
  end

  defp check_box(params, _checked_key), do: {params, nil}

  # The form, and what its values say: the qualification picked, the warnings on the
  # dates, and whether the award is over already.
  defp assign_changeset(socket, changeset) do
    %{qualifications: qualifications, latest: latest, now: now, current_team: team} =
      socket.assigns

    form = to_form(changeset, as: "certificate")
    selected = CertificateExpiry.find(qualifications, to_string(form[:qualification_id].value))
    starts_on = date(form[:starts_on].value)
    ends_on = date(form[:ends_on].value)
    award = selected && latest[selected.id]
    today = Service.Period.today(now, team.timezone)
    default = Certificate.default_ends_on(starts_on, selected, award)

    assign(socket,
      form: form,
      selected: selected,
      selected_award: award,
      warnings: Certificate.date_warnings(starts_on, ends_on, default, today),
      expired?: Certificate.expired_by?(ends_on, today)
    )
  end

  defp date(%Date{} = date), do: date
  defp date(text), do: CertificateExpiry.parse_date(text)

  defp assign_decline_form(socket, params, errors \\ []),
    do: assign(socket, :decline_form, to_form(params, as: "decline", errors: errors))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Certificates" path={~p"/teams/#{@current_team}/certificates"} />
      <:item label={@page_title} />
    </.breadcrumbs>
    <h1 class="title">
      {if @certificate.qualification,
        do: @certificate.qualification.title,
        else: "Certificate from #{@certificate.member.name}"}
    </h1>

    <.banner
      :if={@certificate.status == :waiting and Certificate.dates_locked?(@certificate)}
      id="certificate-not-uploaded"
      kind={:warning}
      title="The certificate did not upload"
    >
      <p>
        The award was sent, but its certificate did not upload. Send again to upload it.
      </p>
      <p :if={error = attach_error(@certificate)} class="hint">{error}</p>
    </.banner>

    <%!-- The award starts the certificate's day (QualificationAward.starts_on?/2). D4H
      keeps it at midnight UTC, the day before on a Canadian clock. --%>
    <.banner
      :if={@existing}
      id="certificate-existing"
      kind={:warning}
      title="This member has this award already"
    >
      <p>
        {Member.first_name(@certificate.member)} holds {CertificateText.title(@certificate)} from {Format.date_short(
          @certificate.starts_on
        )}, {if @existing.certificate?,
          do: "with a certificate. Decline this one.",
          else:
            "with no certificate. Attach certificate puts this file on that award and adds no second one."}
      </p>
    </.banner>

    <div class="cert-layout">
      <div class="cert-layout-file">
        <.certificate_file
          certificate={@certificate}
          src={file_path(@current_team, @certificate, @accepted_award)}
        />
      </div>
      <aside class="cert-layout-panel">
        <dl id="certificate-details" class="mb-8">
          <dt>Member</dt>
          <dd>
            <.a navigate={~p"/teams/#{@current_team}/members/#{@certificate.member_id}"}>{@certificate.member.name}</.a>
          </dd>
          <dt>Sent</dt>
          <dd>{Format.datetime_short(@certificate.inserted_at, @current_team.timezone)}</dd>
          <div :if={@certificate.note}>
            <dt>Note from {Member.first_name(@certificate.member)}</dt>
            <dd id="certificate-note">{@certificate.note}</dd>
          </div>
          <div :if={@certificate.status == :waiting and @selected}>
            <dt>{@selected.title} on record now</dt>
            <dd id="certificate-latest">
              <.latest award={@selected_award} now={@now} timezone={@current_team.timezone} />
            </dd>
          </div>
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

        <div :if={@certificate.status == :accepted} id="certificate-fix">
          <p class="action">
            <.a external={true} href={D4H.member_url(%{@certificate.member | team: @current_team})}>Open {@service} member</.a>
          </p>
          <p class="hint">Wrong qualification or dates? Fix the award in {@service}.</p>
        </div>

        <section
          :if={@certificate.status == :waiting and !(@existing && @existing.certificate?)}
          id="certificate-accept-section"
        >
          <h2 class="subheading">Accept</h2>
          <.form for={@form} id="accept-form" phx-change="validate" phx-submit="accept">
            <.error_summary form={@form} />
            <%= cond do %>
              <% Certificate.dates_locked?(@certificate) -> %>
                <p class="hint">{CertificateText.dates(@certificate)}</p>
              <% @existing -> %>
                <.confirm_box
                  form={@form}
                  selected={@selected}
                  service={@service}
                  team={@current_team}
                />
              <% true -> %>
                <.input
                  field={@form[:qualification_id]}
                  type="combobox"
                  label="Qualification"
                  prompt="Select a qualification"
                  options={@options}
                >
                  {CertificateText.pick_hint(
                    @certificate,
                    @selected && @selected.id,
                    @selected && Map.has_key?(@latest, @selected.id)
                  )}
                </.input>
                <.input field={@form[:starts_on]} type="date" label="Start" />
                <.input field={@form[:ends_on]} type="date" label="Expiry (optional)">
                  {expiry_hint(@expiry, @form, @expired?)}
                </.input>
                <.warning_text :if={@warnings != []} id="certificate-date-warnings" class="mb-6">
                  Check the dates against the certificate.
                  <ul class="list-disc pl-6">
                    <li :for={warning <- @warnings}>
                      {CertificateText.date_warning(warning, @selected)}
                    </li>
                  </ul>
                </.warning_text>
                <.confirm_box
                  form={@form}
                  selected={@selected}
                  service={@service}
                  team={@current_team}
                />
            <% end %>
            <.form_actions>
              <.button
                id="certificate-accept"
                variant={:success}
                phx-disable-with="Sending…"
              >
                {accept_label(@certificate, @existing)}
              </.button>
            </.form_actions>
          </.form>
        </section>

        <section :if={@certificate.status == :waiting} id="certificate-decline" class="mt-8">
          <h2 class="subheading">Decline</h2>
          <.warning_text :if={Certificate.dates_locked?(@certificate)} class="mb-4">
            The award stays. Declining deletes only the certificate.
            <span :if={!D4H.records?(@current_team)}>Only {@service} can remove the award.</span>
          </.warning_text>
          <.form for={@decline_form} id="decline-form" phx-submit="decline">
            <.input field={@decline_form[:reason]} type="textarea" rows="3" label="Why not">
              {Member.first_name(@certificate.member)} sees this on Your membership.
            </.input>
            <.form_actions>
              <.button
                id="certificate-decline-button"
                variant={:danger}
                phx-disable-with="Declining…"
              >
                Decline certificate
              </.button>
            </.form_actions>
          </.form>
        </section>
      </aside>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :selected, :map, default: nil
  attr :service, :string, required: true
  attr :team, :map, required: true

  # The box names what goes to the service: the qualification picked and the dates.
  defp confirm_box(assigns) do
    %{form: form, selected: selected} = assigns
    starts_on = date(form[:starts_on].value)
    ends_on = date(form[:ends_on].value)
    assigns = assign(assigns, label: CertificateText.confirm_label(selected, starts_on, ends_on))

    ~H"""
    <%!-- A Records team changes and removes awards in SAR Duty. --%>
    <.input :if={D4H.records?(@team)} field={@form[:confirmed]} type="checkbox" label={@label} />
    <.input :if={!D4H.records?(@team)} field={@form[:confirmed]} type="checkbox" label={@label}>
      Once it is sent, only {@service} can change or remove the award.
    </.input>
    """
  end

  # "Filled in: X lasts 3 years.", and whether it is over already.
  defp expiry_hint(expiry, form, expired?) do
    filled =
      with {qualification, months} <- CertificateExpiry.hint(expiry, form),
           do: "Filled in: #{qualification.title} lasts #{Format.months(months)}."

    expired = if expired?, do: "Already expired. It goes on record as a past award."
    [filled, expired] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  attr :certificate, :map, required: true
  attr :src, :string, default: nil

  # A photo as an image, a PDF in the browser's own viewer. The frame has no `sandbox`
  # attribute: it would block Chrome's viewer, and the file's own header sandboxes it.
  # An accepted one opens through its award, which may have gone from D4H since.
  defp certificate_file(%{src: nil, certificate: %{status: :accepted}} = assigns) do
    ~H"""
    <p id="certificate-file-gone" class="hint">
      SAR Duty deleted its copy of the file when the certificate was accepted. The award has no certificate now.
    </p>
    """
  end

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
      <%!-- A photo the camera held sideways turns before it goes to D4H. Above the
        photo, the buttons stay put as it turns.
        cspell:ignore uturn -- Heroicons' arrow-uturn icons; it has no rotate icon --%>
      <.form_actions
        :if={@certificate.status == :waiting and @certificate.content_type == "image/jpeg"}
        class="mb-2"
      >
        <.button
          id="certificate-rotate-left"
          phx-click="rotate"
          phx-value-direction="left"
        >
          <.icon name="hero-arrow-uturn-left-mini" /> Rotate left
        </.button>
        <.button
          id="certificate-rotate-right"
          phx-click="rotate"
          phx-value-direction="right"
        >
          <.icon name="hero-arrow-uturn-right-mini" /> Rotate right
        </.button>
      </.form_actions>
      <div class="cert-view">
        <a :if={@certificate.content_type != "application/pdf"} href={@src} target="_blank">
          <img
            id="certificate-image"
            src={@src}
            alt={"#{@certificate.member.name}'s certificate"}
          />
        </a>
        <iframe
          :if={@certificate.content_type == "application/pdf"}
          id="certificate-pdf"
          src={@src}
          title={"#{@certificate.member.name}'s certificate"}
        ></iframe>
      </div>
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
    <span :if={@award.starts_at}>From {Format.date_short(@award.starts_at, @timezone)}</span>
    <span :if={@award.ends_at} class="hint block">{ends(@award, @now, @timezone)}</span>
    """
  end

  # When it ends, in the words of the member's qualifications: "Until Nov 30, 2026" or
  # "Expired Sep 30, 2024".
  defp ends(award, now, timezone) do
    text = QualificationText.expires(award, now, timezone)
    if MemberQualificationAward.expired?(award, now), do: text, else: "Until #{text}"
  end

  # A new address each time the file changes, so a turned photo loads again.
  defp file_path(team, %Certificate{status: :waiting} = certificate, _award),
    do:
      ~p"/teams/#{team}/certificates/#{certificate.id}/file?#{[v: DateTime.to_unix(certificate.updated_at, :millisecond)]}"

  defp file_path(
         team,
         %Certificate{status: :accepted} = certificate,
         %{d4h_document_id: id} = award
       )
       when is_integer(id),
       do: ~p"/teams/#{team}/members/#{certificate.member_id}/certificates/#{award.id}"

  defp file_path(_team, _certificate, _award), do: nil

  defp attach_error(%Certificate{change_set: %{rows: rows}}) do
    Enum.find_value(rows, &(&1.action == :attach_award_document and &1.error))
  end

  defp attach_error(_certificate), do: nil

  defp accept_label(certificate, existing) do
    cond do
      Certificate.dates_locked?(certificate) -> "Send again"
      existing -> "Attach certificate"
      true -> "Accept certificate"
    end
  end

  def handle_event("validate", %{"certificate" => params}, socket),
    do: {:noreply, assign_form(socket, params, :validate)}

  def handle_event("accept", params, socket) do
    %{current_team: team, current_user: user, certificate: certificate} = socket.assigns
    values = params["certificate"] || %{}

    case AcceptCertificate.call(team, certificate, values, user, DateTime.utc_now()) do
      {:ok, accepted} ->
        {:noreply, accepted(socket, Repo.preload(accepted, [:member, :qualification]))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_changeset(socket, changeset)}

      {:error, :decided} ->
        {:noreply, decided(socket)}

      {:error, text} ->
        socket
        |> put_flash(:error, text)
        |> load(certificate.id)
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("rotate", %{"direction" => direction}, socket)
      when direction in ["left", "right"] do
    %{current_team: team, certificate: certificate} = socket.assigns

    case SaveCertificate.rotate(team, certificate, String.to_existing_atom(direction)) do
      {:ok, turned} ->
        {:noreply,
         assign(socket,
           certificate: %{
             certificate
             | file_size: turned.file_size,
               updated_at: turned.updated_at
           }
         )}

      # The page opens again rather than reading D4H here, so the buttons need no
      # phx-disable-with, which would drop their icons (LiveView restores only text).
      {:error, :decided} ->
        socket
        |> put_flash(:error, "Another team admin has decided this certificate.")
        |> push_navigate(to: ~p"/teams/#{team}/certificates/#{certificate.id}")
        |> then(&{:noreply, &1})

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "SAR Duty cannot turn this file.")}
    end
  end

  def handle_event("decline", %{"decline" => %{"reason" => reason}}, socket) do
    %{current_team: team, current_user: user, certificate: certificate} = socket.assigns

    case SaveCertificate.decline(team, certificate, reason, user, DateTime.utc_now()) do
      {:ok, _declined} ->
        socket
        |> put_flash(
          :info,
          if(certificate.qualification,
            do: "Declined #{certificate.qualification.title} for #{certificate.member.name}.",
            else: "Declined the certificate from #{certificate.member.name}."
          )
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
      "Accepted #{CertificateText.title(certificate)} for #{certificate.member.name}."
    )
    |> push_navigate(to: ~p"/teams/#{socket.assigns.current_team}/certificates")
  end

  defp decided(socket) do
    socket
    |> put_flash(:error, "Another team admin has decided this certificate.")
    |> load(socket.assigns.certificate.id)
  end
end
