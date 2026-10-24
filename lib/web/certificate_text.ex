defmodule Web.CertificateText do
  @moduledoc """
  The words for certificates (#493), so the member's pages and the team admin's say the
  same thing.
  """

  alias Service.Format

  @doc "The certificate's qualification, or a stand-in once D4H has deleted it."
  def title(%{qualification: %{title: title}}), do: title
  def title(_certificate), do: "Deleted qualification"

  @doc ~s(Its dates: "Oct 18, 2026 to Oct 18, 2029", or the start alone with no expiry.)
  def dates(%{starts_on: starts_on, ends_on: nil}), do: Format.date_short(starts_on)

  def dates(%{starts_on: starts_on, ends_on: ends_on}),
    do: "#{Format.date_short(starts_on)} to #{Format.date_short(ends_on)}"

  @doc """
  The qualifications to pick from, for the combobox: the member's own first, then every
  other the team has. `own_ids` are the ones the member holds or held, headed
  `own_label`.
  """
  def qualification_options(qualifications, own_ids, own_label) do
    {own, others} = Enum.split_with(qualifications, &MapSet.member?(own_ids, &1.id))
    pairs = fn list -> Enum.map(list, &{&1.title, &1.id}) end

    case {own, others} do
      {[], _others} -> pairs.(others)
      {_own, []} -> pairs.(own)
      _both -> [{own_label, pairs.(own)}, {"Other qualifications", pairs.(others)}]
    end
  end
end
