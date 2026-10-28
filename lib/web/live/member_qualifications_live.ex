defmodule Web.MemberQualificationsLive do
  use Web, {:live_view_app_layout, access: :team}

  on_mount {Web.Components.MemberPage, :own_page}

  import Web.Components.FileDrop
  import Web.Components.MemberPage
  import Web.Components.MemberSidebar, only: [load_sidebar: 1]

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Qualification
  alias App.Model.Team
  alias App.Operation.AwardQualification
  alias App.Repo
  alias App.ViewData.MemberRecords
  alias App.ViewModel.AwardFormViewModel
  alias Web.QualificationText

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(socket.assigns.current_team, params["id"])

    team = socket.assigns.current_team

    socket =
      socket
      |> assign(:page_title, "#{member.name} · Qualifications")
      |> assign(:member, member)
      |> assign_awards()
      |> load_sidebar()
      |> assign(:records?, D4H.records?(team))
      |> assign(:organization_name, Team.organization_name(team) || "Your organization")
      |> assign(
        :qualifications,
        team.id |> Qualification.get_all() |> Enum.map(&{&1.title, &1.id})
      )
      |> assign_award_form(AwardFormViewModel.changeset(%AwardFormViewModel{}))
      |> allow_upload(:certificate,
        accept: ~w(image/* application/pdf),
        max_entries: 1,
        max_file_size: Service.CertificateFile.max_bytes()
      )

    {:noreply, socket}
  end

  # Awarding and removing qualifications, for a team on SAR Duty Records (docs/records.md).
  def handle_event("validate-award", %{"award" => params}, socket) do
    changeset =
      %AwardFormViewModel{} |> AwardFormViewModel.changeset(params) |> Map.put(:action, :validate)

    {:noreply, assign_award_form(socket, changeset)}
  end

  def handle_event("award", %{"award" => params}, socket) do
    %{current_team: team, current_user: user, member: member} = socket.assigns
    true = socket.assigns.records?

    # A certificate (#493) is read once the form is right, so a mistake doesn't lose it,
    # and checked before anything is awarded.
    with {:ok, _values} <- AwardFormViewModel.validate(%AwardFormViewModel{}, params),
         {:ok, certificate} <- certificate(socket),
         :ok <-
           AwardQualification.award(team, member, params, user, DateTime.utc_now(), certificate) do
      {:noreply, reload(socket, "Qualification awarded.")}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_award_form(socket, changeset)}
      # The award is in, so the list shows it and the form starts over: never a second.
      {:award_only, text} -> {:noreply, reload(socket, text, :error)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :certificate, ref)}

  def handle_event("remove-award", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns
    true = socket.assigns.records?
    award = find_award(socket.assigns.awards, id)

    # Gone already, say from another tab.
    result =
      if award, do: AwardQualification.remove(team, award, user, DateTime.utc_now()), else: :gone

    case result do
      :ok -> {:noreply, reload(socket, "Removed #{award.qualification.title}.")}
      :gone -> {:noreply, reload(socket, "That qualification was removed already.")}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

  defp reload(socket, text, kind \\ :info) do
    member = find_member(socket.assigns.current_team, socket.assigns.member.id)

    socket
    |> put_flash(kind, text)
    |> assign(:member, member)
    |> assign_awards()
    |> assign_award_form(AwardFormViewModel.changeset(%AwardFormViewModel{}))
  end

  defp assign_awards(socket),
    do:
      assign(
        socket,
        :awards,
        MemberRecords.qualifications(socket.assigns.member, DateTime.utc_now())
      )

  # Among the awards on the page, which are the member's on this team.
  defp find_award(rows, id) do
    rows
    |> Enum.flat_map(&[&1.award | &1.earlier])
    |> Enum.find(&(Integer.to_string(&1.id) == id))
  end

  defp assign_award_form(socket, changeset),
    do: assign(socket, :award_form, to_form(changeset, as: "award"))

  def render(assigns) do
    ~H"""
    <.member_page
      current_member={@current_member}
      member={@member}
      tab={:qualifications}
      last_attended_at={@last_attended_at}
      standing={@standing}
      milestones={@milestones}
      equipment={@equipment}
      field_rows={@field_rows}
      maps_app={@current_user.maps_app}
      team_admin?={@team_admin?}
    >
      <.qualifications_content
        member={@member}
        awards={@awards}
        records?={@records?}
        team_admin?={@team_admin?}
        organization_name={@organization_name}
      />
      <.award_form
        :if={@team_admin? and @records?}
        form={@award_form}
        qualifications={@qualifications}
        upload={@uploads.certificate}
      />
    </.member_page>
    """
  end

  defp qualifications_content(assigns) do
    assigns = assign(assigns, :now, DateTime.utc_now())

    ~H"""
    <.table
      :if={@awards != []}
      id="member-qualifications"
      rows={@awards}
      row_id={&"member-qualifications-#{&1.award.qualification_id}"}
      row_class={&QualificationText.row_class/1}
    >
      <%!-- A member gets no Certificate (#440), since D4H marks the documents RESTRICTED,
      and no links to qualification pages, which are team admins'. --%>
      <:col :let={row} label="Qualification">
        <.a
          :if={@team_admin?}
          navigate={~p"/teams/#{@member.team}/qualifications/#{row.award.qualification.id}"}
        >{row.award.qualification.title}</.a>
        <span :if={!@team_admin?}>{row.award.qualification.title}</span>
        <span :if={row.award.qualification.organization_owned} class="hint">
          · {@organization_name}
        </span>
        <span :if={@team_admin? and row.award.d4h_document_id} class="hint block">
          <.a
            id={"certificate-#{row.award.id}"}
            href={~p"/teams/#{@member.team}/members/#{@member}/certificates/#{row.award.id}"}
          >Certificate</.a>
        </span>
      </:col>
      <:col :let={row} label="Expires" class="w-px whitespace-nowrap">
        {QualificationText.expires(row.award, @now, @member.team.timezone)}
        <.badge :if={row.status == :expiring} kind={:warning}>
          {QualificationText.days_left(row)}
        </.badge>
      </:col>
      <:col :let={row} label="First held" class="w-px whitespace-nowrap">
        {QualificationText.first_held(row, @member.team.timezone)}
      </:col>
      <:col :let={row} label="Earlier awards" class="w-px whitespace-nowrap">
        <span
          :for={award <- row.earlier}
          id={"member-qualifications-award-#{award.id}"}
          class="flex items-center gap-2"
        >
          {QualificationText.held(award, @member.team.timezone)}
          <.remove_button :if={@team_admin? and @records?} award={award} member={@member} />
        </span>
      </:col>
      <:col :let={row} :if={@team_admin? and @records?} class="w-px whitespace-nowrap">
        <.remove_button award={row.award} member={@member} />
      </:col>
    </.table>
    <p :if={@awards == []} id="no-qualifications">
      {@member.name} has no qualifications.
    </p>
    """
  end

  attr :award, :map, required: true
  attr :member, :map, required: true

  defp remove_button(assigns) do
    ~H"""
    <.button
      id={"remove-award-#{@award.id}"}
      type="button"
      variant={:link}
      size={:sm}
      phx-click="remove-award"
      phx-disable-with="Removing…"
      phx-value-id={@award.id}
      data-confirm={"Remove #{@award.qualification.title} from #{@member.name}?"}
    >
      Remove
    </.button>
    """
  end

  attr :form, :map, required: true
  attr :qualifications, :list, required: true
  attr :upload, :map, required: true

  defp award_form(assigns) do
    ~H"""
    <section id="award-qualification" class="mt-8">
      <h2 class="heading">Award a qualification</h2>
      <p :if={@qualifications == []}>
        Add the qualification on the team's qualifications page first.
      </p>
      <.form
        :if={@qualifications != []}
        for={@form}
        id="award-form"
        phx-change="validate-award"
        phx-submit="award"
        class="measure"
      >
        <.error_summary form={@form} />
        <.input
          field={@form[:qualification_id]}
          type="combobox"
          label="Qualification"
          prompt="Select a qualification"
          options={@qualifications}
        />
        <div class="grid md:grid-cols-2 gap-x-6">
          <.input field={@form[:starts_on]} type="date" label="Start" />
          <.input field={@form[:ends_on]} type="date" label="End (optional)" />
        </div>
        <.file_drop
          id="award-certificate"
          upload={@upload}
          label="Certificate (optional)"
          kinds="a photo or a PDF"
        >
          A photo or a PDF, up to {Service.Format.file_size(Service.CertificateFile.max_bytes())}.
        </.file_drop>
        <.form_actions>
          <.button variant={:success} phx-disable-with="Awarding…">Award qualification</.button>
        </.form_actions>
      </.form>
    </section>
    """
  end

  defp certificate(socket) do
    case consume_uploaded_entries(socket, :certificate, fn %{path: path}, entry ->
           {:ok, {File.read!(path), entry.client_name}}
         end) do
      [] -> {:ok, nil}
      [{bytes, name}] -> Service.CertificateFile.prepare(bytes, name)
    end
  end

  defp find_member(team, member_id),
    do: team |> Member.find!(member_id) |> Repo.preload(:team)
end
