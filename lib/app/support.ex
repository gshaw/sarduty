defmodule App.Support do
  @moduledoc """
  How people reach the SAR Duty site admins, the people who run SAR Duty (#780). The site
  admins are the users SAR Duty makes admins, each named as their member is.
  """

  import Ecto.Query

  alias App.Accounts
  alias App.Model.Member
  alias App.Repo

  @email "support@sarduty.com"

  @doc "SAR Duty's own address, for replies to its notices."
  def email, do: @email

  @doc """
  The SAR Duty site admins, by name, as `%{name:, email:}`: each admin user's email, named
  by a current member with that email, else the email. Get help lists them and sends to
  them. With no admins, as on a new dev database, the support address stands in.
  """
  def site_admins(now \\ DateTime.utc_now()) do
    emails = Enum.map(Accounts.admin_emails(), &String.downcase/1)

    names =
      Member
      |> where([m], fragment("lower(?)", m.email) in ^emails)
      |> Member.current_query(now)
      |> select([m], {fragment("lower(?)", m.email), m.name})
      |> Repo.all()
      |> Map.new()

    case emails do
      [] ->
        [%{name: "SAR Duty site admins", email: @email}]

      emails ->
        emails
        |> Enum.map(&%{email: &1, name: names[&1] || &1})
        |> Enum.sort_by(&String.downcase(&1.name))
    end
  end
end
