defmodule Web.Components.TeamManagers do
  @moduledoc """
  Who can log in to a team: its D4H managers, flagged where odd, and the emails an admin
  let in. Shared by a team's managers page and /admin.
  """
  use Web, :function_component

  import Web.Components.UI

  alias App.Model.Member

  attr :id, :string, required: true
  attr :managers, :list, required: true
  attr :grants, :list, default: []
  attr :login_emails, :any, required: true, doc: "a MapSet of lowercase user emails"

  def team_managers(assigns) do
    ~H"""
    <div id={@id}>
      <p :if={@managers == []} class="text-sm text-secondary-1">
        None known. The team hasn't refreshed since access levels were added, or its key fails.
      </p>
      <ul class="text-sm">
        <li
          :for={member <- @managers}
          id={"manager-#{member.id}"}
          class="flex flex-wrap items-baseline gap-2"
        >
          <span>{member.name}</span>
          <span class="text-secondary-1">{Member.permission_label(member.d4h_permission)}</span>
          <span>{member.email}</span>
          <.badge :if={has_login?(member, @login_emails)} kind={:primary}>Has logged in</.badge>
          <.badge :if={odd_domain?(member, @managers)} kind={:warning}>Other domain</.badge>
          <.badge :if={member.d4h_status != "OPERATIONAL"}>Not operational</.badge>
        </li>
      </ul>
      <ul :if={@grants != []} class="text-sm">
        <li
          :for={grant <- @grants}
          id={"grant-#{grant.id}"}
          class="flex flex-wrap items-baseline gap-2"
        >
          <span>{grant.email}</span>
          <.badge kind={:warning}>Let in by admin</.badge>
          <span :if={grant.reason} class="text-secondary-1">{grant.reason}</span>
        </li>
      </ul>
    </div>
    """
  end

  defp has_login?(member, login_emails),
    do: member.email != nil and MapSet.member?(login_emails, String.downcase(member.email))

  # The team's most common manager email domain is its usual one.
  defp odd_domain?(member, managers) do
    usual =
      managers
      |> Enum.map(&email_domain/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1), fn -> {nil, 0} end)
      |> elem(0)

    usual != nil and email_domain(member) != usual
  end

  defp email_domain(%{email: email}) when is_binary(email) do
    case String.split(email, "@") do
      [_, domain] -> String.downcase(domain)
      _ -> nil
    end
  end

  defp email_domain(_member), do: nil
end
