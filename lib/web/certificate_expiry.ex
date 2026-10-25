defmodule Web.CertificateExpiry do
  @moduledoc """
  The expiry a certificate's form fills in (#493), on the member's form and the team
  admin's: from D4H's length for the qualification, or else the member's last award of
  it. It fills in again when the qualification or the start changes, unless someone typed
  their own. Blank stays blank: it never expires.
  """

  alias App.Model.Certificate

  # filled: the value it filled in. key: the {qualification id, start} it last saw.
  # fill: {qualification, months} behind the value, for the hint.
  defstruct filled: nil, key: nil, fill: nil

  @doc "A new form's, or a saved certificate's: its expiry counts as filled in."
  def new(nil), do: %__MODULE__{}

  def new(%Certificate{} = certificate) do
    %__MODULE__{
      filled: certificate.ends_on && Date.to_iso8601(certificate.ends_on),
      key: {certificate.qualification_id, certificate.starts_on}
    }
  end

  @doc """
  The form's params with the expiry filled in, and the state for next time.
  `latest` is the member's latest award by qualification id.
  """
  def fill(%__MODULE__{} = state, params, qualifications, latest) do
    qualification = find(qualifications, params["qualification_id"])
    starts_on = parse_date(params["starts_on"])
    key = {qualification && qualification.id, starts_on}

    cond do
      key == state.key -> {params, state}
      params["ends_on"] not in [nil, "", state.filled] -> {params, %{state | key: key}}
      true -> fill_default(%{state | key: key}, params, qualification, starts_on, latest)
    end
  end

  defp fill_default(state, params, qualification, starts_on, latest) do
    award = qualification && latest[qualification.id]

    case Certificate.default_ends_on(starts_on, qualification, award) do
      {ends_on, months} ->
        value = Date.to_iso8601(ends_on)

        {Map.put(params, "ends_on", value),
         %{state | filled: value, fill: {qualification, months}}}

      nil ->
        {Map.put(params, "ends_on", ""), %{state | filled: nil, fill: nil}}
    end
  end

  @doc "`{qualification, months}` while the expiry is still the one filled in, else nil."
  def hint(%__MODULE__{filled: filled, fill: fill}, form) do
    if fill && filled != nil && date_text(form[:ends_on].value) == filled, do: fill
  end

  defp date_text(%Date{} = date), do: Date.to_iso8601(date)
  defp date_text(text), do: text

  def find(qualifications, id), do: Enum.find(qualifications, &(to_string(&1.id) == id))

  def parse_date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  def parse_date(_text), do: nil
end
