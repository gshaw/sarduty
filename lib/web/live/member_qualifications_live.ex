defmodule Web.MemberQualificationsLive do
  use Web, :live_view_app_layout

  import Web.Components.MemberSidebar
  import Web.Components.MemberTabs

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Qualification
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
      |> assign(
        :qualifications,
        team.id |> Qualification.get_all() |> Enum.map(&{&1.title, &1.id})
      )
      |> assign_award_form(AwardFormViewModel.changeset(%AwardFormViewModel{}))

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

    case AwardQualification.award(team, member, params, user, DateTime.utc_now()) do
      :ok -> {:noreply, reload(socket, "Qualification awarded.")}
      {:error, %Ecto.Changeset{} = changeset} -> {:noreply, assign_award_form(socket, changeset)}
      {:error, text} -> {:noreply, put_flash(socket, :error, text)}
    end
  end

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

  defp reload(socket, text) do
    member = find_member(socket.assigns.current_team, socket.assigns.member.id)

    socket
    |> put_flash(:info, text)
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
    <.member_head member={@member} last_attended_at={@last_attended_at} standing={@standing} />
    <.member_tabs member={@member} active_tab={:qualifications} equipment={@equipment} />
    <div class="content-wrapper">
      <aside class="content-1/3">
        <.sidebar_content
          member={@member}
          maps_app={@current_user.maps_app}
          milestones={@milestones}
        />
      </aside>
      <main class="content-2/3">
        <.qualifications_content member={@member} awards={@awards} records?={@records?} />
        <.award_form :if={@records?} form={@award_form} qualifications={@qualifications} />
      </main>
    </div>
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
      <:col :let={row} label="Qualification">
        <.a navigate={~p"/teams/#{@member.team}/qualifications/#{row.award.qualification.id}"}>{row.award.qualification.title}</.a>
        <span :if={row.award.d4h_document_id} class="hint block">
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
          <.remove_button :if={@records?} award={award} member={@member} />
        </span>
      </:col>
      <:col :let={row} :if={@records?} class="w-px whitespace-nowrap">
        <.remove_button award={row.award} member={@member} />
      </:col>
    </.table>
    <p :if={@awards == []} id="no-qualifications">
      {@member.name} has no qualifications in {D4H.service_name(@member.team)}.
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
      phx-value-id={@award.id}
      data-confirm={"Remove #{@award.qualification.title} from #{@member.name}?"}
    >
      Remove
    </.button>
    """
  end

  attr :form, :map, required: true
  attr :qualifications, :list, required: true

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
        <.form_actions>
          <.button variant={:success}>Award qualification</.button>
        </.form_actions>
      </.form>
    </section>
    """
  end

  defp find_member(team, member_id),
    do: team |> Member.find!(member_id) |> Repo.preload(:team)
end
