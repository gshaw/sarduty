defmodule Web.AgentAuthorizeLive do
  use Web, :live_view_narrow_layout

  alias App.Model.AgentClient
  alias App.Model.Team
  alias App.Operation.AuthorizeAgent

  # Allowing an AI agent (#761), /teams/:subdomain/oauth/authorize. The agent sends the
  # admin here; logging in comes first if needed. A team admin sees Allow, anyone else
  # learns who can connect, and a web agent SAR Duty doesn't know is refused by its
  # return address. Allow and Cancel post to Web.OAuthController, which reads the
  # request again and sends the admin back to the agent. Only the agent's name changes
  # from one agent to the next. A team with Agents off is not found.

  # What the form carries back; the controller checks it all again.
  @request_keys ~w(client_id redirect_uri state code_challenge code_challenge_method
                   response_type resource)

  @doc """
  The team's name when a page logging in returns to is this one, so the login pages say
  what logging in is for; nil otherwise.
  """
  def login_team_name(path) when is_binary(path) do
    with [_path, subdomain] <- Regex.run(~r{^/teams/([^/?]+)/oauth/authorize(?:\?|$)}, path),
         %Team{} = team <- Web.OAuthController.enabled_team(subdomain) do
      team.name
    else
      _other -> nil
    end
  end

  def login_team_name(_path), do: nil

  def mount(%{"subdomain" => subdomain} = params, _session, socket) do
    team = Web.OAuthController.enabled_team(subdomain) || raise Web.Status.NotFound
    client = AgentClient.get_by_client_id(params["client_id"])
    socket = assign(socket, team: team, page_title: "Connect an AI agent?")

    case AuthorizeAgent.check(params, client, Web.OAuthController.mcp_url(team.subdomain)) do
      {:ok, request} -> {:ok, assign_request(socket, team, request, params)}
      {:redirect, url} -> {:ok, redirect(socket, external: url)}
      {:unknown_agent, host} -> {:ok, assign(socket, status: :unknown, host: host)}
      {:bad_link, message} -> {:ok, assign(socket, status: :bad_link, message: message)}
    end
  end

  defp assign_request(socket, team, request, params) do
    user = socket.assigns.current_user
    admin? = Team.managed_by?(team, user.email, DateTime.utc_now())

    assign(socket,
      status: if(admin?, do: :allow, else: :not_admin),
      request: request,
      fields: Map.take(params, @request_keys),
      deny_url: AuthorizeAgent.deny_url(request)
    )
  end

  def render(%{status: :allow} = assigns) do
    ~H"""
    <h1 class="title">Connect an AI agent?</h1>
    <p id="agent-asks">
      <strong id="agent-name">{@request.name}</strong>
      asks to read {@team.name}’s data in SAR Duty: members, groups, activities and their
      attendance, hours, chores, qualifications, and change history. It only reads.
    </p>
    <.warning_text id="agent-warning">
      {@request.name} will see your members’ names, hours, and history.
    </.warning_text>
    <p class="hint">
      Check the agent’s settings: it should not train on your chats. Work and API accounts
      often do not by default.
    </p>
    <.form for={%{}} id="agent-authorize-form" action={~p"/teams/#{@team}/oauth/authorize"}>
      <input :for={{key, value} <- @fields} type="hidden" name={key} value={value} />
      <.form_actions>
        <.button id="agent-allow" name="decision" value="allow" variant={:success}>
          Allow
        </.button>
        <.button id="agent-cancel" name="decision" value="cancel">Cancel</.button>
      </.form_actions>
    </.form>
    <.logged_in_as user={@current_user} />
    """
  end

  def render(%{status: :not_admin} = assigns) do
    ~H"""
    <h1 class="title">You cannot connect an agent</h1>
    <p id="agent-not-admin">Only team admins can connect an agent to {@team.name}.</p>
    <p>
      <.a id="agent-back" href={@deny_url}>Back to {@request.name}</.a>
    </p>
    <.logged_in_as user={@current_user} />
    """
  end

  def render(%{status: :unknown} = assigns) do
    ~H"""
    <h1 class="title">SAR Duty does not know this agent</h1>
    <p id="agent-unknown">
      It sends you back to <strong id="agent-host">{@host}</strong>, which is not on SAR
      Duty’s list. Email support@sarduty.com with the agent’s name to
      have it added.
    </p>
    <p>Agents on your computer, and Claude and ChatGPT on the web, work now.</p>
    <.logged_in_as user={@current_user} />
    """
  end

  def render(%{status: :bad_link} = assigns) do
    ~H"""
    <h1 class="title">This link does not work</h1>
    <p id="agent-bad-link">{@message}</p>
    <.logged_in_as user={@current_user} />
    """
  end

  attr :user, :map, required: true

  defp logged_in_as(assigns) do
    ~H"""
    <p class="hint mt-6">Logged in as {@user.email}.</p>
    """
  end
end
