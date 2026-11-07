defmodule App.Operation.PrintTaxCreditLetter do
  @moduledoc """
  Prints a tax credit letter from its document, priv/documents/tax_credit_letter.txt
  (#918): runs the document's reports for the member and year, adds the pictures and
  the PDF's reference and verify link, and prints it with Typst
  (App.Operation.PrintDocument). Only App.Operation.SaveTaxCreditLetterPDF and
  App.Operation.LoadTaxCreditLetterPDF print: everything else serves the saved PDF.

  A letter prints its own hours, reference number, and date certified, so one made
  before letters kept their PDF prints what it says.
  """

  alias App.Document
  alias App.Model.DemoTeam
  alias App.Model.TaxCreditLetter
  alias App.Model.Team
  alias App.Operation.PrintDocument
  alias App.Operation.ReadDocument
  alias App.Report.Context

  @document "tax_credit_letter"

  @doc """
  The checked document and the values it reads for `member_id` and `year`, as of
  `now`: `%{doc, values}`, from App.Operation.ReadDocument.
  """
  def read(%Team{} = team, member_id, year, now) do
    # Counts only this member's year, which the document's hours report filters to.
    context = Context.new(team, now, hours_for: {member_id, year})
    starts = %{member: member_id, year: year}
    {:ok, read} = @document |> Document.read() |> ReadDocument.call(context, starts)
    read
  end

  @doc """
  A new letter's fields from `read/4`: its text and the hours it keeps. The PDF is
  printed from the same values, so the two agree.
  """
  def fields(%{doc: doc, values: values}, %Team{} = team, ref_id) do
    output = Document.evaluate(doc, Map.put(values, "pdf.reference", ref_id), team.timezone)

    %{
      ref_id: ref_id,
      primary_minutes: output.keep["hours.primary"] || 0,
      secondary_minutes: output.keep["hours.secondary"] || 0,
      letter_content: Document.text(output, "letter")
    }
  end

  @doc """
  The letter's PDF: `{:ok, attachment}` or `{:error, reason}`. Expects its member and
  team loaded. `read` is `read/4`'s, when the caller has it already.
  """
  def call(%TaxCreditLetter{} = letter, read \\ nil) do
    team = letter.member.team
    output = output(letter, read)

    with {:ok, pdf} <- PrintDocument.call(output, sample: DemoTeam.demo?(team)) do
      {:ok,
       %{
         content: pdf,
         title: output.title,
         filename: Service.StringHelpers.to_filename("#{output.title}.pdf"),
         content_type: "application/pdf"
       }}
    end
  end

  @doc "What `call/2` prints: the document evaluated with the letter's own values."
  def output(%TaxCreditLetter{} = letter, read \\ nil) do
    team = letter.member.team

    %{doc: doc, values: values} =
      read || read(team, letter.member_id, letter.year, letter.inserted_at || DateTime.utc_now())

    Document.evaluate(doc, Map.merge(values, own_values(letter)), team.timezone)
  end

  # What the letter says, whatever attendance says now. A letter from before the hours
  # were saved (#260) reads them from attendance.
  defp own_values(letter) do
    hours =
      if letter.primary_minutes && letter.secondary_minutes,
        do: %{
          "hours.primary" => letter.primary_minutes,
          "hours.secondary" => letter.secondary_minutes,
          "hours.total" => letter.primary_minutes + letter.secondary_minutes
        },
        else: %{}

    Map.merge(hours, %{"pdf.reference" => letter.ref_id, "pdf.verify_link" => qr_url(letter)})
  end

  @doc """
  What the letter's QR code opens: its page on the verify site. Nil for a letter from
  before #207, which has no verify line and a reference number that can't verify alone.
  """
  def qr_url(letter) do
    if TaxCreditLetter.current_ref_id?(letter),
      do: TaxCreditLetter.verify_url(letter, Web.VerifyHost.url())
  end
end
