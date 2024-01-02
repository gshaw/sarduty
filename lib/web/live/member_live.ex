defmodule Web.MemberLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = find_member(params["id"])

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(:member, member)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item label="Members" path={~p"/#{@current_team.subdomain}/members/"} />
      <:item label={"##{@member.ref_id}"} />
    </.breadcrumbs>

    <div class="md:flex gap-p w-full">
      <div class="flex-1">
        <h1 class="title"><%= @member.name %></h1>
        <.member_details_table member={@member} />
      </div>
      <div>
        <img
          class="bg-base-0 aspect-square object-cover size-48 rounded"
          src={~p"/#{@current_team.subdomain}/members/#{@member.id}/image"}
        />
      </div>
    </div>
    """
  end

  defp member_details_table(assigns) do
    ~H"""
    <table class="table table-form">
      <tr>
        <th>Role</th>
        <td><%= @member.position %></td>
      </tr>
      <tr>
        <th>Email</th>
        <td><%= @member.email %></td>
      </tr>
      <tr>
        <th>Phone</th>
        <td><%= @member.phone %></td>
      </tr>
      <tr>
        <th>Address</th>
        <td><%= @member.address %></td>
      </tr>
      <tr>
        <th>Actions</th>
        <td>
          <ol class="action-list">
            <li>
              <.a external={true} href={D4H.build_member_url(@member)}>Open D4H Member</.a>
            </li>
            <li>
              <.a href={member_activities_path(@member)}>Member Activities</.a>
            </li>
          </ol>
        </td>
      </tr>
    </table>
    """
  end

  defp member_activities_path(member),
    do: ~p"/#{member.team.subdomain}/members/#{member.id}/activities"

  defp find_member(member_id) do
    Member
    |> Repo.get(member_id)
    |> Repo.preload(:team)
  end
end
