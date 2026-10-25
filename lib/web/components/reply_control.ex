defmodule Web.Components.ReplyControl do
  @moduledoc """
  Sends a member's reply (#444) and shows it with `Web.Components.Reply`.

  Assigns: `team`, `activity`, `member` (from `Reply.replier/2`), `invitation` (their
  attendance row), `user`, `viewing_as`, and `size`, `:sm` in a list row. `viewing_as`
  is required, nil unless a team admin is viewing as a member. Its events skip the team
  pages' hook (#440), so a page that left it out would send the team admin's reply as
  the member. The page shows it only when `Reply.open?/3`. A reply sends `{:replied, attendance}` to the
  page, which recounts; a refusal sends `{:reply_failed, text}` for the page's flash.
  """
  use Web, :live_component

  import Web.Components.Reply, only: [reply: 1]

  alias App.Model.Member
  alias App.Operation.ReplyToActivity
  alias Web.Components.Reply
  alias Web.UserAuth

  def update(%{viewing_as: _} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:size, fn -> :md end)
     |> assign_new(:changing?, fn -> false end)}
  end

  # A team admin viewing as the member saves nothing.
  def handle_event("reply", _params, %{assigns: %{viewing_as: %Member{} = viewing_as}} = socket) do
    send(self(), {:reply_failed, UserAuth.view_as_refusal(viewing_as)})
    {:noreply, socket}
  end

  def handle_event("reply", %{"reply" => reply}, socket) when reply in ["yes", "no"] do
    %{team: team, activity: activity, member: member, user: user} = socket.assigns

    case ReplyToActivity.call(team, activity, member, answer(reply), user, DateTime.utc_now()) do
      {:ok, attendance} ->
        send(self(), {:replied, attendance})
        {:noreply, assign(socket, invitation: attendance, changing?: false)}

      {:error, text} ->
        send(self(), {:reply_failed, text})
        {:noreply, socket}
    end
  end

  def handle_event("change", _params, socket), do: {:noreply, assign(socket, changing?: true)}

  defp answer("yes"), do: :yes
  defp answer("no"), do: :no

  def render(assigns) do
    ~H"""
    <div id={"#{@id}-control"} class="reply-control">
      <.reply
        id={@id}
        state={Reply.state(@invitation, @changing?)}
        size={@size}
        target={@myself}
        calendar_href={~p"/teams/#{@team}/activities/#{@activity.id}/calendar"}
      />
    </div>
    """
  end
end
