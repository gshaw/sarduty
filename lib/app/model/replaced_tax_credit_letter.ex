defmodule App.Model.ReplacedTaxCreditLetter do
  use App, :model

  import Ecto.Query

  alias App.Model.ReplacedTaxCreditLetter
  alias App.Model.TaxCreditLetter
  alias App.Repo

  # What a letter said before Replace gave it a new reference number (#207). The member
  # may already have handed in the paper copy, so its reference number still verifies,
  # with the hours it printed. `inserted_at` is when it was replaced.
  schema "replaced_tax_credit_letters" do
    belongs_to :tax_credit_letter, TaxCreditLetter
    field :ref_id, :string
    field :primary_minutes, :integer
    field :secondary_minutes, :integer
    field :certified_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "The row that keeps `letter` checkable once it's replaced at `now`."
  def from_letter(%TaxCreditLetter{} = letter, now) do
    %ReplacedTaxCreditLetter{
      tax_credit_letter_id: letter.id,
      ref_id: letter.ref_id,
      primary_minutes: letter.primary_minutes,
      secondary_minutes: letter.secondary_minutes,
      certified_at: letter.inserted_at,
      inserted_at: DateTime.add(now, 0, :microsecond)
    }
  end

  @doc """
  The replaced letter with this reference number, with the letter that replaced it and
  its member. An old reference number also needs the member's last name, as for
  `TaxCreditLetter.find_by_ref_id/2`.
  """
  def find_by_ref_id({:current, ref_id}) do
    ref_id |> query() |> Repo.all() |> List.first()
  end

  def find_by_ref_id({:old, ref_id}, last_name) do
    ref_id
    |> query()
    |> Repo.all()
    |> Enum.filter(&TaxCreditLetter.last_name_matches?(&1.tax_credit_letter.member, last_name))
    |> only_one()
  end

  defp only_one([replaced]), do: replaced
  defp only_one(_none_or_several), do: nil

  defp query(ref_id) do
    ReplacedTaxCreditLetter
    |> where([r], r.ref_id == ^ref_id)
    |> order_by([r], desc: r.inserted_at)
    |> preload(tax_credit_letter: [member: :team])
  end
end
