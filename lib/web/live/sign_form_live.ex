defmodule Web.SignFormLive do
  @moduledoc """
  The page a task leader signs a form on when a team admin asked them (#993,
  App.Operation.AskToSign): page 1 of the PDF as it publishes, with their signature, and
  Sign and publish, which publishes it signed in their name
  (App.Operation.PublishDocument.publish_asked/5). With a value the form needs blank, it
  says so and has no button.

  Only the member asked opens it, signed in as themselves: a member who logs in, or a
  team admin found by their email. Anyone else gets a 404. Once the request ends, the
  page says so. A team admin viewing as the member sees it without the PDF, since only
  the member signs.
  """
  use Web, {:live_view_app_layout, access: :team, member_events: ["sign"]}

  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.Member
  alias App.Model.SignRequest
  alias App.Operation.AskToSign
  alias App.Operation.PublishDocument
  alias App.Operation.ReadDocument
  alias App.ViewData.ActivityForms

  def mount(%{"id" => id, "form_id" => form_id}, _session, socket) do
    team = socket.assigns.current_team
    now = DateTime.utc_now()
    activity = Activity.find!(team, id)
    form = Form.get_shown(team, form_id) || raise(Web.Status.NotFound)
    member = signer(socket.assigns, now) || raise(Web.Status.NotFound)
    request = request(member, %{activity | team: team}, form, now) || raise(Web.Status.NotFound)

    socket =
      assign(socket,
        page_title: "Sign #{request.title}",
        activity: activity,
        form: form,
        request: request,
        asked_by: Member.name_for_user(team, request.asked_by, now),
        needed: [],
        preview: nil
      )

    {:ok, socket |> assign_needed(now) |> start_preview()}
  end

  # The member signing: the one a member logs in as, or a team admin's own, by email.
  # Viewing as a member, it's that member.
  defp signer(%{current_member: %Member{} = member}, _now), do: member

  defp signer(%{team_admin?: true, current_team: team, current_user: user}, now),
    do: Member.find_by_email(team, user.email, now)

  defp signer(_assigns, _now), do: nil

  # The member's newest request for the form, ended now if the Task Leader's Name no
  # longer names them.
  defp request(member, activity, form, now) do
    case SignRequest.latest_for(member, activity, form) do
      nil ->
        nil

      request ->
        request = %{request | team: activity.team, activity: activity, form: form, member: member}
        AskToSign.current(request, now) || SignRequest.latest_for(member, activity, form)
    end
  end

  defp assign_needed(%{assigns: %{request: request}} = socket, now) do
    %{current_team: team, activity: activity, form: form} = socket.assigns

    if SignRequest.open?(request) do
      case ActivityForms.load(team, activity, form, now) do
        {:ok, page} -> assign(socket, needed: page.needed)
        {:error, _reason} -> assign(socket, needed: [])
      end
    else
      socket
    end
  end

  # Printing takes a moment, so it runs once connected. A team admin viewing as the
  # member gets no preview: only the member signs.
  defp start_preview(%{assigns: %{request: request, needed: []}} = socket) do
    if SignRequest.open?(request) and is_nil(socket.assigns.viewing_as) and connected?(socket),
      do: print(socket),
      else: socket
  end

  defp start_preview(socket), do: socket

  defp print(socket) do
    %{current_user: user, current_team: team} = socket.assigns
    request = full(socket)
    current = ActivityForms.published(team, request.activity, request.form).current

    socket
    |> assign(preview: :printing, preview_current_id: current && current.id)
    |> start_async(:preview, fn ->
      with {:ok, preview} <- PublishDocument.preview_asked(request, user, DateTime.utc_now()),
           {:ok, [page | _rest]} <- Service.PDFImages.pages(preview.printed.attachment.content) do
        {:ok, Map.put(preview, :page, page)}
      end
    end)
  end

  # The request with what publishing reads: its team, activity, form, and member.
  defp full(socket) do
    %{request: request, current_team: team, activity: activity, form: form} = socket.assigns
    member = request.member || App.Repo.preload(request, :member).member
    %{request | team: team, activity: %{activity | team: team}, form: form, member: member}
  end

  def handle_async(:preview, {:ok, {:ok, preview}}, socket),
    do: {:noreply, assign(socket, preview: preview)}

  def handle_async(:preview, {:ok, {:error, message}}, socket),
    do: {:noreply, socket |> assign(preview: nil) |> put_flash(:error, message)}

  def handle_async(:preview, {:exit, _reason}, socket),
    do:
      {:noreply,
       socket |> assign(preview: nil) |> put_flash(:error, "The PDF did not print. Reload.")}

  def handle_event("sign", _params, %{assigns: %{preview: %{code: _code} = preview}} = socket) do
    %{current_user: user, preview_current_id: current_id} = socket.assigns
    request = full(socket)

    case PublishDocument.publish_asked(request, user, preview, current_id, DateTime.utc_now()) do
      {:ok, _pdf} ->
        signed = SignRequest.latest_for(request.member, request.activity, request.form)

        {:noreply,
         socket
         |> assign(request: signed, preview: nil)
         |> put_flash(:info, "Signed and published #{request.title}.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("sign", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={@activity.ref_id || @activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label="Sign" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <%= if SignRequest.open?(@request) do %>
      <p id="sign-asked" class="lead measure">
        {@asked_by || "A team admin"} asked you to sign it for {@activity.title} on {Service.Format.date_short(
          @request.asked_at,
          @current_team.timezone
        )}. Check page 1, then sign.
      </p>
      <.banner
        :if={@needed != []}
        id="sign-needed"
        kind={:warning}
        title="Needed to publish"
        class="measure"
      >
        <p>{ReadDocument.needed_error("This form", @needed)}</p>
        <p :if={@team_admin?}>
          Fill it in on <.a
            id="sign-needed-fix"
            navigate={~p"/teams/#{@current_team}/activities/#{@activity.id}/forms/#{@form.id}"}
          >the form's page</.a>, then come back to sign.
        </p>
        <p :if={!@team_admin? and Enum.any?(@needed, &is_nil(ReadDocument.waits_for(&1)))}>
          Ask {@asked_by || "a team admin"} to fill it in, then come back to sign.
        </p>
      </.banner>

      <div :if={@needed == []} class="content-wrapper">
        <aside class="content-1/3">
          <h2 class="heading">Signature</h2>
          <p id="sign-signature">/s/ {@request.member.name}</p>
          <p class="hint mb-6">
            Dated today. Signing publishes it for {@current_team.name}, and {@asked_by ||
              "the team admin who asked"} gets the PDF.
          </p>
          <p :if={@viewing_as} id="sign-viewing-as" class="hint">
            Only {@request.member.name} can sign it.
          </p>
          <p :if={@preview == :printing} class="hint">Printing the PDF…</p>
          <.form_actions :if={is_nil(@viewing_as)}>
            <.button
              id="sign-confirm"
              type="button"
              variant={:primary}
              phx-click="sign"
              phx-disable-with="Signing…"
              disabled={!is_map(@preview)}
            >
              Sign and publish
            </.button>
          </.form_actions>
        </aside>
        <main class="content-2/3">
          <img
            :if={is_map(@preview)}
            id="sign-page-1"
            src={"data:image/png;base64," <> Base.encode64(@preview.page)}
            alt={"Page 1 of the #{@request.title} as it publishes, signed by #{@request.member.name}"}
            class="w-full border border-border-subtle shadow-sm"
          />
        </main>
      </div>
    <% else %>
      <.banner
        id="sign-ended"
        kind={ended_kind(@request)}
        title={ended_title(@request)}
        class="measure"
      >
        <p>{ended_why(@request, @current_team, @asked_by)}</p>
      </.banner>
    <% end %>
    """
  end

  defp ended_kind(%{ended_why: :signed}), do: :success
  defp ended_kind(_request), do: :info

  defp ended_title(%{ended_why: :signed}), do: "You signed it"
  defp ended_title(_request), do: "This request has ended."

  defp ended_why(%{ended_why: :signed} = request, team, asked_by) do
    day = Service.Format.date_short(request.ended_at, team.timezone)
    "It was published on #{day}, and #{asked_by || "the team admin who asked"} got the PDF."
  end

  defp ended_why(%{ended_why: :signed_for}, _team, _asked_by),
    do: "A team admin signed it for you, and you got the PDF by email."

  defp ended_why(%{ended_why: :leader_changed}, _team, _asked_by),
    do: "The form no longer names you as its task leader."

  defp ended_why(_request, _team, _asked_by), do: "There's nothing for you to sign."
end
