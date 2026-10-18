defmodule App.Model.MemberStandingChange do
  use App, :model

  alias App.Accounts.User
  alias App.Model.Member
  alias App.Model.MemberStandingChange
  alias App.Model.Team
  alias App.Repo

  # What a team admin changed in a member's standing (#366), for the member's history.
  # `details` keeps an away period's reason and dates as strings, since the period can be
  # deleted.
  schema "member_standing_changes" do
    belongs_to :team, Team
    belongs_to :member, Member
    belongs_to :user, User

    field :action, Ecto.Enum,
      values: [:away_added, :away_ended, :away_deleted, :not_a_person, :person]

    field :details, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert!(%MemberStandingChange{} = change), do: Repo.insert!(change)

  @doc "The details an away period's change keeps."
  def period_details(period) do
    %{
      "reason" => period.reason,
      "starts_on" => Date.to_iso8601(period.starts_on),
      "ends_on" => Date.to_iso8601(period.ends_on)
    }
  end

  def for_member(team_id, member_id, limit) do
    MemberStandingChange
    |> where([c], c.team_id == ^team_id and c.member_id == ^member_id)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end
end
