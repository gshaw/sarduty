defmodule Web.TeamSignupLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Operation.SignUpTeam
  alias App.ViewModel.TeamSignupViewModel
  alias Web.SecurityEvent

  def mount(_params, session, socket) do
    socket =
      assign(socket,
        client_ip: session["client_ip"],
        user_agent: get_connect_info(socket, :user_agent)
      )

    changeset = TeamSignupViewModel.build_new_changeset(%{api_host: D4H.default_region()})
    {:ok, socket |> assign(page_title: "Sign up a team", done: nil) |> assign_form(changeset)}
  end

  def render(assigns) do
    ~H"""
    <div :if={@done} id="signup-done">
      <h1 class="heading">{@done.name} is on SAR Duty</h1>
      <p>
        Its first refresh from {D4H.service_name(@done.api_host)} has started and takes a few minutes. We've emailed
        <strong>{@done.email}</strong>
        a code to log in. It works once, for 15 minutes.
      </p>
      <.form_actions>
        <.button variant={:success} navigate={~p"/login/code?#{[email: @done.email]}"}>
          Enter your code
        </.button>
      </.form_actions>
    </div>
    <div :if={!@done}>
      <h1 class="heading">Sign up a team</h1>
      <p id="signup-d4h">
        SAR Duty works from your team's D4H data. You need a D4H access key from a D4H member
        with Owner or Editor access. Best is a member named "SAR Duty", so changes show as SAR
        Duty in D4H. You must also be an Owner or Editor on the team in D4H.
      </p>
      <p>
        <.a external={true} href="https://help.d4h.com/article/377-obtaining-an-api-access-key">
          How to create a D4H access key
        </.a>
      </p>
      <%!-- Almost every team has D4H. Records is a trial, so it gets one line. --%>
      <p id="signup-records" class="hint">
        No D4H?
        <.a external={true} href={"https://#{D4H.records_host()}"}>SAR Duty Records</.a>
        is an experimental place to keep your team's records. Select it as the region and paste a
        Records access key.
      </p>
      <.form for={@form} id="signup_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:email]} type="email" label="Email" autocomplete="email">
          The email {D4H.service_name(@api_host)} has for you. We send your login code here.
        </.input>
        <.input
          field={@form[:api_host]}
          type="select"
          label="D4H region"
          options={D4H.services()}
        />
        <.input
          field={@form[:access_key]}
          type="password"
          label={D4H.key_name(@api_host)}
          autocomplete="off"
        />
        <.form_actions>
          <.button
            variant={:success}
            phx-disable-with={"Checking with #{D4H.service_name(@api_host)}…"}
          >
            Sign up
          </.button>
        </.form_actions>
      </.form>
      <p class="text-text-muted">
        Already on SAR Duty?
        <.a navigate={~p"/login"}>Log in</.a>
      </p>
    </div>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    changeset = TeamSignupViewModel.build_new_changeset(params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    who = SecurityEvent.who(params["email"] || "")

    case SignUpTeam.call(params) do
      {:ok, team} ->
        SecurityEvent.record(socket.assigns, :team_signed_up, team_id: team.id, data: %{who: who})
        done = %{name: team.name, email: params["email"], api_host: team.d4h_api_host}
        {:noreply, assign(socket, done: done)}

      {:error, changeset} ->
        fields = changeset.errors |> Keyword.keys() |> Enum.uniq()
        data = %{who: who, fields: fields}
        SecurityEvent.record(socket.assigns, :team_signup_failed, data: data)
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # The page's words follow the chosen service. Anything off the list reads as D4H.
  defp assign_form(socket, changeset) do
    api_host = Ecto.Changeset.get_field(changeset, :api_host)
    api_host = if api_host in D4H.service_hosts(), do: api_host, else: D4H.default_region()
    assign(socket, form: to_form(changeset, as: "form"), api_host: api_host)
  end
end
