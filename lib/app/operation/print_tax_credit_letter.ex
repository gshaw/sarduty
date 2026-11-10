defmodule App.Operation.PrintTaxCreditLetter do
  @moduledoc """
  Prints a tax credit letter from its document, priv/documents/tax_credit_letter.txt
  (#918): runs the document's reports for the member and year, adds the pictures, and
  prints it with Typst (App.Operation.PrintDocument), with the verify code of the ID it's
  published under (#970). Only App.Operation.PublishTaxCreditLetter prints what's kept:
  everything else serves the saved PDF. A draft, for the letter page's preview before
  there's a letter, is never kept. The document also writes the letter's email
  (`email to member`) and says which team settings it needs (`needs`).
  """

  alias App.Document
  alias App.Document.Evaluator
  alias App.Model.DemoTeam
  alias App.Model.PublishedPDF
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
  `read/4` for many members' letters for `year` at once, by member id (#995): their hours
  counted once, and the document checked once. The letters list reads every letter it
  shows this way, to say which are out of date.
  """
  def read_each(%Team{}, [], _year, _now), do: %{}

  def read_each(%Team{} = team, member_ids, year, now) do
    context = Context.new(team, now, hours_for: {member_ids, year})
    starts = Enum.map(member_ids, &%{member: &1, year: year})
    {:ok, reads} = @document |> Document.read() |> ReadDocument.call_each(context, starts)
    member_ids |> Enum.zip(reads) |> Map.new()
  end

  @doc """
  What the letter from `read/4` would keep, and its verify page show, if it were
  published today: `%{keep, shows}`, as `call/3` saves them. Out of date compares them
  with a published letter's (App.Model.TaxCreditLetter.changes/4).
  """
  def today(%Team{} = team, %{doc: doc, values: values}),
    do: doc |> Document.evaluate(values, team.timezone) |> kept()

  # A member with no hours keeps 0, as the letter prints.
  defp kept(output),
    do: %{
      keep: Map.new(output.keep, fn {name, value} -> {name, value || 0} end),
      shows: output.shows
    }

  @doc """
  The letter's PDF from `read/4`, published under the ID `code`: `{:ok, %{attachment,
  keep, shows, name, code}}`, what App.Model.PublishedPDF.publish/3 saves, or `{:error,
  reason}`.
  """
  def call(%Team{} = team, %{doc: doc, values: values}, code) do
    link = PublishedPDF.verify_link(code)
    output = Document.evaluate(doc, Map.put(values, "pdf.verify_link", link), team.timezone)
    mark = if DemoTeam.demo?(team), do: :sample

    with {:ok, pdf} <- PrintDocument.call(output, mark: mark, verify: link) do
      {:ok,
       output
       |> kept()
       |> Map.merge(%{
         attachment: %{
           content: pdf,
           title: output.title,
           filename: Service.StringHelpers.to_filename("#{output.title}.pdf"),
           content_type: "application/pdf"
         },
         name: doc.name,
         code: code
       })}
    end
  end

  @doc """
  The letter from `read/4` as it prints today, marked DRAFT, for the letter page's
  picture before there's a letter: `{:ok, pdf}` or `{:error, reason}`. It signs as the
  letter will, /s/ and the signer's name (#995), and a grey box takes the verify code's
  place. The picture is never downloaded.
  """
  def draft(%Team{} = team, %{doc: doc, values: values}) do
    values = Map.put(values, "pdf.verify_link", nil)
    output = Document.evaluate(doc, values, team.timezone)
    PrintDocument.call(output, mark: :draft, verify: :draft)
  end

  @doc "The letter's text from `read/4`, as it prints, for a test or a check."
  def text(%Team{} = team, %{doc: doc, values: values}),
    do: doc |> Document.evaluate(values, team.timezone) |> Document.text("letter")

  @doc """
  The letter's email to its member, `%{subject, body}`, as of `now`: the document's
  `email to member`, read again, so it names the team's signer as they are now.
  """
  def email(%PublishedPDF{member: %{team: team}} = letter, now) do
    %{doc: doc, values: values} = read(team, letter.member_id, letter.year, now)
    Document.evaluate(doc, values, team.timezone).email
  end

  @doc """
  The names of the values the letter `needs`, in its order, such as
  `["team.mailing_address", "team.signer", "team.signer_title"]`: the Signer tab marks a
  blank one in its preview.
  """
  def need_names do
    {:ok, doc} = @document |> Document.read() |> Document.parse()
    Enum.map(doc.needs, &Evaluator.name/1)
  end

  @doc """
  What the letter from `read/4` needs to publish that's blank, the document's `needs`
  (ReadDocument.needed/3): `[]` when it can be published. Publishing refuses while
  there's one (#995).
  """
  def needed(%{doc: doc, values: values, read: read}), do: ReadDocument.needed(doc, values, read)

  @doc """
  The team's settings the letter needs that it hasn't filled in, the document's `needs`
  (#943), as `needed/1` names them: `%{name: "team.signer_title", label: "Signer's
  title", …}`. They keep every letter from being published, so Needs attention and
  the letters list name them.
  """
  def missing_settings(%Team{} = team, now) do
    {:ok, %{doc: doc, values: values, read: read}} =
      @document |> Document.read() |> ReadDocument.settings(Context.new(team, now))

    doc
    |> ReadDocument.needed(values, read)
    |> Enum.filter(&(&1.from in ~w(team organization)))
  end
end
