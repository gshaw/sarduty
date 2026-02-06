defmodule App.Model.MemberQualificationAward do
  use App, :model

  alias App.Model.Member
  alias App.Model.MemberQualificationAward
  alias App.Model.Qualification
  alias App.Repo

  schema "member_qualification_awards" do
    belongs_to :member, Member
    belongs_to :qualification, Qualification
    field :d4h_award_id, :integer
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%MemberQualificationAward{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :member_id,
      :qualification_id,
      :d4h_award_id,
      :starts_at,
      :ends_at
    ])
    |> validate_required([
      :member_id,
      :qualification_id,
      :d4h_award_id
    ])
  end

  def get_by(params), do: Repo.get_by(MemberQualificationAward, params)

  def insert!(params) do
    changeset = MemberQualificationAward.build_new_changeset(params)
    Repo.insert!(changeset)
  end

  def update!(%MemberQualificationAward{} = record, params) do
    changeset = MemberQualificationAward.build_changeset(record, params)
    Repo.update!(changeset)
  end
end
