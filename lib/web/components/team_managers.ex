defmodule Web.Components.TeamManagers do
  @moduledoc """
  Who can log in to a team: its D4H managers, flagged where odd, and the emails an admin
  let in. Shared by a team's managers page and /admin.
  """
  use Web, :function_component

  import Web.Components.Table

  alias App.Model.Member

  attr :id, :string, required: true
  attr :managers, :list, required: true
  attr :grants, :list, default: []
  attr :login_emails, :any, required: true, doc: "a MapSet of lowercase user emails"

  def team_managers(assigns) do
    assigns = assign(assigns, :rows, rows(assigns))

    ~H"""
    <div>
      <p :if={@rows == []} class="hint">
        None known. The team has not refreshed since SAR Duty added access levels, or its D4H access key does not work.
      </p>
      <.table :if={@rows != []} id={@id} rows={@rows} row_id={& &1.id} class="table-striped">
        <:col :let={row} label="Team admin">
          <div :if={row.name}>{row.name}</div>
          <div class={["break-all", row.name && "text-sm text-text-muted"]}>{row.email}</div>
        </:col>
        <:col :let={row} label="Access">
          <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
            <span>{row.access}</span>
            <.badge :for={{kind, text} <- row.badges} kind={kind}>{text}</.badge>
          </div>
          <div :if={row.reason} class="hint">{row.reason}</div>
        </:col>
      </.table>
    </div>
    """
  end

  # Managers first, by name, then the emails an admin let in.
  defp rows(%{managers: managers, grants: grants, login_emails: login_emails}) do
    manager_rows =
      for member <- managers do
        badges =
          [
            has_login?(member, login_emails) && {:primary, "Has logged in"},
            odd_domain?(member, managers) && {:warning, "Other email domain"},
            member.d4h_status != "OPERATIONAL" && {:default, "Not operational"}
          ]
          |> Enum.filter(& &1)

        %{
          id: "manager-#{member.id}",
          name: member.name,
          access: Member.permission_label(member.d4h_permission),
          email: member.email,
          badges: badges,
          reason: nil
        }
      end

    grant_rows =
      for grant <- grants do
        %{
          id: "grant-#{grant.id}",
          name: nil,
          access: "Let in by a SAR Duty admin",
          email: grant.email,
          badges: [],
          reason: grant.reason
        }
      end

    manager_rows ++ grant_rows
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
