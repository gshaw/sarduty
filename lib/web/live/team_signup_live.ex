defmodule Web.TeamSignupLive do
  use Web, :live_view_narrow_layout

  alias App.Adapter.D4H
  alias App.Operation.SignUpTeam
  alias App.ViewModel.TeamSignupViewModel

  def mount(_params, _session, socket) do
    changeset = TeamSignupViewModel.build_new_changeset(%{api_host: D4H.default_region()})
    {:ok, socket |> assign(page_title: "Sign up a team", done: nil) |> assign_form(changeset)}
  end

  def render(assigns) do
    ~H"""
    <div :if={@done} id="signup-done">
      <h1 class="heading">{@done.name} is on SAR Duty</h1>
      <p>
        Its first D4H refresh has started and takes a few minutes. We've emailed
        <strong>{@done.email}</strong>
        a link to log in. It works once, for 15 minutes.
      </p>
    </div>
    <div :if={!@done}>
      <h1 class="heading">Sign up a team</h1>
      <p>
        SAR Duty works from your team's D4H data. You need a D4H access key from a D4H member
        with Owner or Editor access. Best is a member named "SAR Duty", so changes show as SAR
        Duty in D4H. You must also be an Owner or Editor on the team in D4H.
      </p>
      <p>
        <.a external={true} href="https://help.d4h.com/article/377-obtaining-an-api-access-key">
          How to create a D4H access key
        </.a>
      </p>
      <.form for={@form} id="signup_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:email]} type="email" label="Your email" autocomplete="email">
          The email D4H has for you. We send your login link here.
        </.input>
        <.input
          field={@form[:api_host]}
          type="select"
          label="D4H region"
          options={D4H.regions()}
        />
        <.input
          field={@form[:access_key]}
          type="password"
          label="D4H access key"
          autocomplete="off"
        />
        <.form_actions>
          <.button variant={:success} phx-disable-with="Checking with D4H…">Sign up</.button>
        </.form_actions>
      </.form>
      <p class="text-secondary-1">
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
    case SignUpTeam.call(params, &url(~p"/login/#{&1}")) do
      {:ok, team} ->
        {:noreply, assign(socket, done: %{name: team.name, email: params["email"]})}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: "form"))
end
