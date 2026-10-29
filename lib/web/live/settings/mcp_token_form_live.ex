defmodule Web.Settings.MCPTokenFormLive do
  use Web, :live_view_app_layout

  import Web.Components.CopyButton

  alias App.Model.Team
  alias App.Operation.CreateMCPToken

  # Creating an MCP token (#28), /teams/:subdomain/settings/mcp/new. Once created, the
  # form gives way to the token, shown only this once, so there is nothing to submit twice.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team
    if !team.mcp_enabled, do: raise(Web.Status.NotFound)

    if !Team.managed_by?(team, socket.assigns.current_user.email, DateTime.utc_now()),
      do: raise(Web.Status.NotFound)

    socket =
      socket
      |> assign(page_title: "Create token", new_token: nil)
      |> assign(endpoint_url: url(~p"/teams/#{team}/mcp"))
      |> assign(:form, to_form(%{}, as: "token"))

    {:ok, socket}
  end

  def handle_event("create", %{"token" => params}, socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case CreateMCPToken.call(team, user, params) do
      {:ok, token, _record} ->
        {:noreply, assign(socket, page_title: "Copy your token", new_token: token)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "token", action: :insert))}

      {:error, :not_allowed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only members with Owner or Editor access in #{socket.assigns.service} can create a token."
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Team settings" path={~p"/teams/#{@current_team}/settings"} />
      <:item label="MCP tokens" path={~p"/teams/#{@current_team}/settings/mcp"} />
      <:item label="Create token" />
    </.breadcrumbs>
    <h1 class="title">{@page_title}</h1>

    <div :if={@new_token} id="new-token" class="measure">
      <p class="font-semibold">SAR Duty shows it only once.</p>
      <.copy_code_block id="new-token-value" value={@new_token} label="Copy token" />
      <p>
        To set it up, paste this into your AI agent. It has the token, so treat it like a
        password.
      </p>
      <.copy_code_block
        id="setup-prompt"
        value={setup_prompt(@endpoint_url, @new_token)}
        label="Copy setup prompt"
      />
      <p>Or, in Claude Code, run this in a terminal:</p>
      <.copy_code_block
        id="claude-code-command"
        value={claude_code_command(@endpoint_url, @new_token)}
        label="Copy command"
      />
      <.form_actions>
        <.button id="token-done" navigate={~p"/teams/#{@current_team}/settings/mcp"}>
          Back to tokens
        </.button>
      </.form_actions>
    </div>

    <.form :if={!@new_token} for={@form} id="new-token-form" class="measure" phx-submit="create">
      <.input field={@form[:name]} label="Name">
        Where you use the token, like "Claude Code on my laptop".
      </.input>
      <.input
        field={@form[:no_training]}
        type="checkbox"
        label="I'll use this token only with an AI service set not to train on my data"
      >
        In Claude, turn off "Help improve Claude". In ChatGPT, turn off "Improve the model
        for everyone". Work and API accounts often do not train by default. Check yours.
      </.input>
      <.form_actions>
        <.button variant={:success} phx-disable-with="Creating…">Create token</.button>
        <.button id="token-cancel" navigate={~p"/teams/#{@current_team}/settings/mcp"}>
          Cancel
        </.button>
      </.form_actions>
    </.form>
    """
  end

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

    The token is a password. Do not print it again or save it anywhere but the MCP \
    settings.\
    """
  end

  defp claude_code_command(url, token) do
    "claude mcp add --transport http sarduty #{url} \\\n" <>
      "  --header \"Authorization: Bearer #{token}\""
  end
end
