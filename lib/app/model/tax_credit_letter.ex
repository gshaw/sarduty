defmodule App.Model.TaxCreditLetter do
  use App, :model

  import Ecto.Query

  alias App.Field.EncryptedString
  alias App.Model.Member
  alias App.Model.TaxCreditLetter
  alias App.Repo

  schema "tax_credit_letters" do
    belongs_to :member, Member
    field :ref_id, :string
    field :year, :integer
    field :letter_content, EncryptedString, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_new_changeset(params \\ %{}), do: build_changeset(%TaxCreditLetter{}, params)

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [
      :ref_id,
      :member_id,
      :year,
      :letter_content
    ])
    |> validate_required([
      :ref_id,
      :member_id,
      :year,
      :letter_content
    ])
    |> validate_number(:year, greater_than_or_equal_to: 2014, less_than: 2100)
  end

  def find(team, id) do
    query =
      from(tcl in TaxCreditLetter,
        left_join: m in assoc(tcl, :member),
        where: tcl.id == ^id,
        where: m.team_id == ^team.id,
        preload: [member: :team]
      )

    Repo.one(query)
  end

  # def get_all do
  #   TaxCreditLetter
  #   |> order_by([t], desc: t.id)
  #   |> Repo.all()
  # end

  # def get(nil), do: nil
  # def get(id), do: Repo.get(TaxCreditLetter, id)
  # def get!(id), do: Repo.get!(TaxCreditLetter, id)
  # def get_by(params), do: Repo.get_by(TaxCreditLetter, params)

  # def update(%TaxCreditLetter{} = tax_credit_letter, params) do
  #   changeset = TaxCreditLetter.build_changeset(tax_credit_letter, params)
  #   Repo.update(changeset)
  # end

  # def delete(%TaxCreditLetter{} = tax_credit_letter), do: Repo.delete(tax_credit_letter)
end
