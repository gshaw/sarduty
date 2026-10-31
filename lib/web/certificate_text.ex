defmodule Web.CertificateText do
  @moduledoc """
  The words for certificates (#493), so the member's pages and the team admin's say the
  same thing.
  """

  use Phoenix.Component

  import Web.Components.Core, only: [input: 1]

  alias App.Model.Member
  alias Service.Format

  attr :checked, :boolean, required: true

  @doc """
  The box a team admin selects to accept their own certificate (#697), as for chores
  (Web.ChoreText.own_box/1). Accept stays off until it is selected.
  """
  def own_box(assigns) do
    ~H"""
    <.input
      type="checkbox"
      id="accept-own"
      name="own"
      value={@checked}
      label="Accept my own certificate"
    >
      I know another team admin should accept the certificates I send. I'm making an exception.
    </.input>
    """
  end

  @doc "The flash when a team admin's own certificate goes to accept without the box checked."
  def own_refused, do: "Select Accept my own certificate to accept yours."

  @doc """
  The certificate's qualification, or "Certificate" when it has none: the member did not
  pick one, or it was deleted.
  """
  def title(%{qualification: %{title: title}}), do: title
  def title(_certificate), do: "Certificate"

  @doc "The question before a member deletes their certificate."
  def delete_question(%{qualification: %{title: title}}),
    do: "Delete your #{title} certificate?"

  def delete_question(_certificate), do: "Delete this certificate?"

  @doc """
  The hint under the team admin's qualification: whether the member picked it, and
  whether they have held it before. Nil when there is nothing to say.
  """
  def pick_hint(certificate, selected_id, held?) do
    first = Member.first_name(certificate.member)

    who =
      cond do
        is_nil(selected_id) and is_nil(certificate.qualification_id) ->
          "#{first} did not select one. Read it from the certificate."

        selected_id == certificate.qualification_id ->
          "#{first} selected this. Check it against the certificate."

        true ->
          nil
      end

    new = if selected_id && !held?, do: "New for #{first}: no award of it yet."

    case Enum.reject([who, new], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  @doc "One line for each of `App.Model.Certificate.date_warnings/4`."
  def date_warning(:starts_after_today, _qualification), do: "The start is after today."

  def date_warning({:length, usual, months}, qualification),
    do:
      "#{qualification.title} lasts #{Format.months(usual)}. These dates are #{Format.months(months)} apart."

  def date_warning({:no_expiry, usual}, qualification),
    do: "#{qualification.title} lasts #{Format.months(usual)}, and this has no expiry."

  @doc "The box a team admin selects once they have checked the certificate."
  def confirm_label(nil, _starts_on, _ends_on),
    do: "I checked the qualification and dates against the certificate."

  def confirm_label(_qualification, nil, _ends_on),
    do: "I checked the qualification and dates against the certificate."

  def confirm_label(qualification, starts_on, ends_on),
    do:
      "I checked the certificate. It is #{qualification.title}, #{dates(%{starts_on: starts_on, ends_on: ends_on})}."

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
