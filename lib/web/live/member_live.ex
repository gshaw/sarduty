defmodule Web.MemberLive do
  use Web, :live_view_app_layout

  alias App.Adapter.D4H
  alias App.Model.Member

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    member = Member.get!(params["id"])

    socket =
      socket
      |> assign(:page_title, member.name)
      |> assign(:member, member)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="mb-p05 text-sm">
      <.a navigate={~p"/#{@current_team.subdomain}"}><%= @current_team.name %></.a>
      /
      <.a navigate={~p"/#{@current_team.subdomain}/members/"}>Members</.a>
    </div>

    <div class="md:flex gap-p w-full">
      <div class="flex-1">
        <h1 class="title"><%= @member.name %></h1>
        <h3 class="subheading">
          → <.a
            external={true}
            external_icon_class="w-6 h-6"
            href={D4H.build_member_url(@current_team, @member)}
            phx-no-format
          >Open D4H Member</.a>
        </h3>
        <table class="table mb-p">
          <tr>
            <th>Role</th>
            <td><%= @member.position %></td>
          </tr>
          <tr>
            <th>ID</th>
            <td><%= @member.ref_id %></td>
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
        </table>
      </div>
      <div class="">
        <p>
          <img
            class="bg-base-0 aspect-square object-cover size-48 rounded"
            src={~p"/#{@current_team.subdomain}/members/#{@member.id}/image"}
          />
        </p>
      </div>
    </div>
    """
  end
end
