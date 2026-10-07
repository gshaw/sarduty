defmodule Web.Settings.MCPLive do
  use Web, :live_view_narrow_layout

  alias App.Model.MCPToken
  alias App.Model.Team
  alias App.Operation.CreateMCPToken
  alias App.Operation.RevokeMCPToken

  # The team's MCP tokens (#28), /teams/:subdomain/settings/mcp. Only on a team an admin
  # turned MCP on for; anywhere else the page doesn't exist.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.mcp_enabled, do: raise(Web.Status.NotFound)

    can_create = Team.managed_by?(team, socket.assigns.current_user.email, DateTime.utc_now())

    socket =
      socket
      |> assign(page_title: "MCP tokens", can_create: can_create, new_token: nil)
      |> assign(endpoint_url: url(~p"/teams/#{team}/mcp"))
      |> assign_form(%{})
      |> assign_tokens()

    {:ok, socket}
  end

  defp assign_form(socket, params), do: assign(socket, :form, to_form(params, as: "token"))

  defp assign_tokens(socket),
    do: assign(socket, :tokens, MCPToken.get_live_for_team(socket.assigns.current_team))

  def handle_event("create", %{"token" => params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case CreateMCPToken.call(team, user, params) do
      {:ok, token, _record} ->
        socket =
          socket
          |> assign(new_token: token)
          |> assign_form(%{})
          |> assign_tokens()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "token", action: :insert))}

      {:error, :not_allowed} ->
        {:noreply, put_flash(socket, :error, "Only a D4H Owner or Editor can create a token.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    with {id, ""} <- Integer.parse(id),
         {:ok, token} <- RevokeMCPToken.call(team, id, user) do
      socket =
        socket
        |> assign_tokens()
        |> put_flash(:info, "Token #{token.name} revoked.")

      {:noreply, socket}
    else
      _not_found ->
        {:noreply,
         socket |> assign_tokens() |> put_flash(:error, "That token is already revoked.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <p>
        <.a navigate={~p"/teams/#{@current_team}/settings"}>← Team settings</.a>
      </p>
      <h1 class="heading">MCP tokens</h1>
      <p>
        An MCP token lets your AI agent, such as Claude Code, read {@current_team.name}'s data
        in SAR Duty. It can read members, groups, attendance hours, activities,
        qualifications, and change history.
      </p>
      <p class="mt-p">
        Agents cannot change D4H. They can propose attendance changes, and nothing happens
        until a team admin sends them from Proposed changes. Agents never see email, phone
        numbers, or addresses. SAR Duty logs every request, and SAR Duty admins can read the log.
      </p>
      <p id="no-training" class="mt-p font-semibold">
        Use a token only with an AI service set not to train on your data. The token gives
        it your team members' names, hours, and history.
      </p>
      <p class="mt-p">
        Each token is yours. It stops working when you revoke it, or when D4H no longer makes
        you an Owner or Editor.
      </p>

      <div :if={@new_token} id="new-token" class="callout mt-p">
        <p class="font-semibold">Copy your token now. SAR Duty shows it only once.</p>
        <pre
          id="new-token-value"
          class="my-2 p-p rounded bg-base-2 overflow-x-auto whitespace-pre-wrap break-all"
        >{@new_token}</pre>
        <p class="mt-p">
          To set it up, paste this into your AI agent. It has the token, so treat it like a
          password.
        </p>
        <pre id="setup-prompt" class="my-2 p-p rounded bg-base-2 whitespace-pre-wrap">{setup_prompt(@endpoint_url, @new_token)}</pre>
      </div>

      <.form
        :if={@can_create}
        for={@form}
        id="new-token-form"
        phx-submit="create"
        class="mt-p"
      >
        <.input field={@form[:name]} label="Name">
          Where you use the token, like "Claude Code on my laptop".
        </.input>
        <.input
          field={@form[:no_training]}
          type="checkbox"
          label="I'll use this token only with an AI service set not to train on my data"
        >
          In Claude, turn off "Help improve Claude". In ChatGPT, turn off "Improve the model
          for everyone". Work and API accounts often don't train by default; check yours.
        </.input>
        <.form_actions>
          <.button variant={:success}>Create token</.button>
        </.form_actions>
      </.form>
      <p :if={!@can_create} id="cannot-create" class="mt-p text-secondary-1">
        Only a member D4H makes an Owner or Editor can create a token.
      </p>

      <h2 class="heading mt-p2">Tokens</h2>
      <p :if={@tokens == []} id="no-tokens">No tokens yet. Create one above.</p>
      <.table :if={@tokens != []} id="tokens" rows={@tokens} row_id={&"token-#{&1.id}"}>
        <:col :let={token} label="Name">{token.name}</:col>
        <:col :let={token} label="Owner">{token.user.email}</:col>
        <:col :let={token} label="Created" class="whitespace-nowrap">
          {Service.Format.date_long(token.inserted_at, @current_team.timezone)}
        </:col>
        <:col :let={token} label="Last used" class="whitespace-nowrap">
          {last_used(token, @current_team.timezone)}
        </:col>
        <:col :let={token} label="">
          <.button
            id={"revoke-token-#{token.id}"}
            type="button"
            size={:sm}
            variant={:danger}
            phx-click="revoke"
            phx-value-id={token.id}
            data-confirm={"Revoke the token #{token.name}? Agents that use it stop working right away."}
          >
            Revoke token
          </.button>
        </:col>
      </.table>

      <h2 class="heading mt-p2">Connect an agent</h2>
      <p>
        Agents connect with the token in a header. The claude.ai and ChatGPT connectors cannot
        send one yet.
      </p>
      <h3 class="font-semibold mt-p">Claude Code</h3>
      <p>Run this in a terminal:</p>
      <pre id="claude-code-command" class="my-2 p-p rounded bg-base-2 whitespace-pre-wrap break-all">{claude_code_command(@endpoint_url, @new_token)}</pre>
      <h3 class="font-semibold mt-p">Claude Desktop</h3>
      <p>
        Add this to <code>claude_desktop_config.json</code>, then restart Claude Desktop. It
        needs Node.js, and uses <code>mcp-remote</code> to send the token.
      </p>
      <pre id="claude-desktop-config" class="my-2 p-p rounded bg-base-2 whitespace-pre-wrap break-all">{claude_desktop_config(@endpoint_url, @new_token)}</pre>
    </div>
    """
  end

  defp last_used(%MCPToken{last_used_at: nil}, _timezone), do: "Never"

  defp last_used(%MCPToken{last_used_at: used}, timezone),
    do: Service.Format.minutes_ago(used, DateTime.utc_now(), timezone)

  @placeholder "YOUR_TOKEN"

  defp setup_prompt(url, token) do
    """
    Connect to SAR Duty's MCP server for me. It is a remote MCP server over Streamable \
    HTTP, so it needs no install.

    - Name: sarduty
    - URL: #{url}
    - Header: Authorization: Bearer #{token}

    In Claude Code, run `claude mcp add --transport http sarduty <URL> --header \
    "Authorization: Bearer <token>"`. In another app, add it to that app's MCP settings. \
    Then list its tools to check it works.

    The token is a password. Don't print it again or save it anywhere but the MCP \
    settings.\
    """
  end

  defp claude_code_command(url, token) do
    "claude mcp add --transport http sarduty #{url} \\\n" <>
      "  --header \"Authorization: Bearer #{token || @placeholder}\""
  end

  defp claude_desktop_config(url, token) do
    %{
      "mcpServers" => %{
        "sarduty" => %{
          "command" => "npx",
          "args" => ["mcp-remote", url, "--header", "Authorization:${SARDUTY_AUTH}"],
          "env" => %{"SARDUTY_AUTH" => "Bearer #{token || @placeholder}"}
        }
      }
    }
    |> Jason.encode!(pretty: true)
  end
end
