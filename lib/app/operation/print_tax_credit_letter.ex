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
  The letter's PDF from `read/4`, published under the ID `code`: `{:ok, %{attachment,
  keep, shows, name, code}}`, what App.Model.PublishedPDF.publish/3 saves, or `{:error,
  reason}`. A member with no hours keeps 0, as the letter prints.
  """
  def call(%Team{} = team, %{doc: doc, values: values}, code) do
    link = PublishedPDF.verify_link(code)
    output = Document.evaluate(doc, Map.put(values, "pdf.verify_link", link), team.timezone)
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
         keep: Map.new(output.keep, fn {name, value} -> {name, value || 0} end),
         shows: output.shows,
         name: doc.name,
         code: code
       }}
    end
  end

  @doc """
  The letter from `read/4` as it prints today, marked DRAFT, for the letter page before
  there's a letter: `{:ok, pdf}` or `{:error, reason}`. As a form's draft, it carries no
  signature, and a grey box where the verify code goes.
  """
  def draft(%Team{} = team, %{doc: doc, values: values}) do
    values = Map.merge(values, %{"team.signature" => nil, "pdf.verify_link" => nil})
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
  The settings the letter needs that the team hasn't filled in, the document's `needs`
  (#943), each `%{name, label}`: `%{name: "team.signature", label: "Signer's signature"}`.
  """
  def missing_settings(%Team{} = team, now) do
    {:ok, %{doc: doc, values: values, labels: labels}} =
      @document |> Document.read() |> ReadDocument.settings(Context.new(team, now))

    doc |> Document.missing(values) |> Enum.map(&%{name: &1, label: labels[&1] || &1})
  end
end
