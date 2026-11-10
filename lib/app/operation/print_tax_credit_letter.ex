defmodule App.Operation.PrintTaxCreditLetter do
  @moduledoc """
  Prints a tax credit letter from its document, priv/documents/tax_credit_letter.txt
  (#918): runs the document's reports for the member and year, adds the pictures, and
  prints it with Typst (App.Operation.PrintDocument), with the verify code of the ID
  it's published under (#970). Only App.Operation.SaveTaxCreditLetterPDF prints, when a
  letter is made, replaced, or emailed without a PDF: everything else serves the saved
  PDF.

  A letter prints its own hours and date certified, so one made before letters kept
  their PDF prints what it says.
  """

  alias App.Document
  alias App.Model.DemoTeam
  alias App.Model.PublishedPDF
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
  def fields(%{doc: doc, values: values}, %Team{} = team) do
    output = Document.evaluate(doc, values, team.timezone)

    %{
      primary_minutes: output.keep["hours.primary"] || 0,
      secondary_minutes: output.keep["hours.secondary"] || 0,
      letter_content: Document.text(output, "letter")
    }
  end

  @doc """
  The letter's PDF, published under the ID `code`: `{:ok, %{attachment, keep, shows,
  name, code}}`, what App.Model.PublishedPDF.publish/3 saves, or `{:error, reason}`.
  Expects its member and team loaded. `read` is `read/4`'s, when the caller has it.
  """
  def call(%TaxCreditLetter{} = letter, code, read \\ nil) do
    team = letter.member.team

    read =
      read || read(team, letter.member_id, letter.year, letter.inserted_at || DateTime.utc_now())

    output = output(letter, code, read)
    link = PublishedPDF.verify_link(code)
    mark = if DemoTeam.demo?(team), do: :sample

    with {:ok, pdf} <- PrintDocument.call(output, mark: mark, verify: link) do
      {:ok,
       %{
         attachment: %{
           content: pdf,
           title: output.title,
           filename: Service.StringHelpers.to_filename("#{output.title}.pdf"),
           content_type: "application/pdf"
         },
         keep: output.keep,
         shows: output.shows,
         name: read.doc.name,
         code: code
       }}
    end
  end

  @doc "What `call/3` prints: the document evaluated with the letter's own values."
  def output(%TaxCreditLetter{} = letter, code, %{doc: doc, values: values}) do
    values = Map.merge(values, own_values(letter, code))
    Document.evaluate(doc, values, letter.member.team.timezone)
  end

  # What the letter says, whatever attendance says now. A letter from before the hours
  # were saved (#260) reads them from attendance.
  defp own_values(letter, code) do
    hours =
      if letter.primary_minutes && letter.secondary_minutes,
        do: %{
          "hours.primary" => letter.primary_minutes,
          "hours.secondary" => letter.secondary_minutes,
          "hours.total" => letter.primary_minutes + letter.secondary_minutes
        },
        else: %{}

    Map.put(hours, "pdf.verify_link", PublishedPDF.verify_link(code))
  end
end
