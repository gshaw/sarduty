defmodule App.AI.FormJob do
  @moduledoc """
  An AI writing ask on Change form (#1089), a team's form or an organization's: the
  system prompt, the tools, and the check of Claude's answer (App.AI.Job). Claude gets
  the rules, the form language (App.Document.language/0, docs/documents.md) with the
  report language its queries are written in, and the names for things, each a cache
  breakpoint: a team's own, or for an organization the custom fields every team in it
  has, since its form must hold on each. Then the agency's blank form as a PDF, its
  page's measures (Service.PDFGeometry), the visit's earlier asks with its replies, the
  form's text as it stands, and the ask.

  Never a member, an activity, or a row: the page tries the form on an activity in SAR
  Duty, after Claude is done, and that activity never reaches Claude.
  App.AI.FormJobTest seeds them and checks the request.
  """

  alias App.AI.Job
  alias App.AI.ReportJob
  alias App.AI.Tool.CheckForm
  alias App.Document
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Model.Team
  alias App.Operation.SaveForm
  alias App.Report.Language

  @rules """
  You write a form in SAR Duty, a web app for search and rescue teams: a team's own, or
  an organization's for every team in it. A form is a text in SAR Duty's form language,
  below, that prints an activity's values on the agency's own blank form. An admin
  describes what they want, and you write or rewrite the form's text to do it.

  - Start from the text as it stands and change only what the ask needs. Earlier asks in
    this visit come first, with your replies: the text already has their changes. A form
    with no text yet needs its first draft: read the whole page.
  - The text starts with form and the form's name as it stands, in quotes; keep the name
    unless the ask changes it. It prints on the agency's page, so it says page, and each
    place comes from the page's measures as "Writing a team's form" says. Never guess a
    place from the picture alone.
  - Fill a label from a field: the language's subjects and fields, and the names for
    things given after it.
    Write a custom field by its title in backticks. Add a question (ask) only when the
    admin asks for one. Leave a label blank when nothing holds its value.
  - Check each text with check_form before you answer. It runs every check saving runs.
  - You never see any team's members or records. The admin tries the form on an
    activity in SAR Duty.
  - Answer with the whole text, a note, and what you left blank. The note is one short
    sentence for the admin in plain words: what you changed, or why you could not. No
    tool names, no field names in backticks. Left blank is each label on the page that
    nothing fills, as the page prints it, and why, in one short sentence each, such as
    "No field holds it. Ask for a question, or fill it in by hand."
  - When nothing in the language or the team's fields answers the ask, give "" as the
    text and say in the note what would work instead.
  """

  @schema %{
    "type" => "object",
    "properties" => %{
      "text" => %{"type" => "string"},
      "note" => %{"type" => "string"},
      "blank" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{"label" => %{"type" => "string"}, "why" => %{"type" => "string"}},
          "required" => ["label", "why"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["text", "note", "blank"],
    "additionalProperties" => false
  }

  @doc """
  The job for `form`, a team's or an organization's (`owner`), whose text the page holds
  as `text`, and `ask`. `page`
  is the form's page PDF, the agency's blank form. `earlier` is the visit's asks before
  it, oldest first, each `%{ask:, note:, blank:}`. Its result is `%{text:, note:,
  blank:}`, with `blank` a list of `%{label:, why:}`.
  """
  def build(owner, %Form{} = form, page, text, ask, now, earlier \\ []) do
    %Job{
      kind: :form,
      system: [
        @rules <> "\n" <> Document.language() <> "\n" <> Language.markdown(),
        catalog(owner, now)
      ],
      tools: [CheckForm],
      prompt: prompt(form, page, text, ask, earlier),
      schema: @schema,
      finish: &finish(&1, owner, form, page, text, now),
      context: %{owner: owner, now: now, form: form, page: page},
      ask: ask,
      stream: true
    }
  end

  @on "\nA custom field's `on` is its subject; an activity's is on every kind of activity it's kept for.\n"

  defp catalog(%Team{} = team, _now), do: ReportJob.catalog(team) <> @on

  # An organization's form is checked on every team in it and on Coast Range SAR, so it
  # reads only the custom fields they all have, and no team's own groups or tags.
  defp catalog(%Organization{} = organization, now) do
    contexts = SaveForm.contexts(organization, now)
    teams = Enum.map_join(contexts, ", ", &elem(&1, 0))

    shared =
      contexts
      |> Enum.map(fn {_name, context} -> ReportJob.field_list(context.custom_fields) end)
      |> shared_fields()

    """
    This form is #{organization.name}'s, for every team in it, and it must hold on each:
    #{teams}. Write no group, qualification, or tag, since each team has its own. The
    custom fields every one of them has, as JSON:
    #{Jason.encode!(shared, pretty: true)}
    """ <> @on
  end

  defp shared_fields([]), do: []

  defp shared_fields([first | rest]) do
    key = &Map.take(&1, ["title", "on", "type"])
    keys = Enum.map(rest, fn fields -> MapSet.new(fields, key) end)
    Enum.filter(first, fn field -> Enum.all?(keys, &MapSet.member?(&1, key.(field))) end)
  end

  # The PDF and its measures first, the same bytes every ask on this form, so they cache;
  # then what changes.
  defp prompt(form, page, text, ask, earlier) do
    [
      document(page),
      %{
        "type" => "text",
        "text" => measures(page),
        "cache_control" => %{"type" => "ephemeral"}
      },
      %{"type" => "text", "text" => now_text(form, text, ask, earlier)}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp document(nil), do: nil

  defp document(page),
    do: %{
      "type" => "document",
      "title" => "The agency's blank form",
      "source" => %{
        "type" => "base64",
        "media_type" => "application/pdf",
        "data" => Base.encode64(page)
      }
    }

  @doc "The page's measures, as text, or why there are none."
  def measures(nil), do: "The form has no page."

  def measures(page) do
    case Service.PDFGeometry.read(page) do
      {:ok, pages} ->
        "The page's measures, in points from each page's top left:\n\n" <>
          Service.PDFGeometry.describe(pages)

      {:error, reason} ->
        "SAR Duty could not measure the page: #{reason}"
    end
  end

  defp now_text(form, text, ask, earlier) do
    """
    #{earlier(earlier)}The form is called #{form.name}. Its text as it stands:
    #{text_or_none(text)}

    The admin asks: #{ask}
    """
  end

  defp text_or_none(text) do
    case String.trim(text || "") do
      "" -> "(none yet: write its first draft)"
      text -> "```\n#{text}\n```"
    end
  end

  defp earlier([]), do: ""

  defp earlier(asks) do
    lines =
      Enum.map_join(asks, "\n", fn ask ->
        blank = Enum.map_join(ask[:blank] || [], "; ", & &1.label)
        blank = if blank == "", do: "", else: "\n  You left blank: #{blank}"
        "- The admin asked: #{ask.ask}\n  You noted: #{ask.note || "(none)"}#{blank}"
      end)

    "Earlier asks in this visit, oldest first:\n#{lines}\n\n"
  end

  @doc """
  Checks Claude's answer as saving would, against the owner's fields and the page.
  """
  def finish(output, owner, %Form{} = form, page, text, now) do
    new = String.trim(output["text"] || "")
    note = String.trim(output["note"] || "")

    if new == "" or new == String.trim(text || "") do
      {:unchanged, note}
    else
      case SaveForm.check_for(owner, form, new, page, now) do
        {:ok, _doc} -> {:ok, %{text: new, note: note, blank: blank(output["blank"])}}
        {:error, _field, message} -> {:retry, message}
      end
    end
  end

  defp blank(list) when is_list(list) do
    for %{"label" => label} = item <- list, String.trim(label) != "" do
      %{label: String.trim(label), why: String.trim(item["why"] || "")}
    end
  end

  defp blank(_none), do: []
end
