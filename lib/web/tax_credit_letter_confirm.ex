defmodule Web.TaxCreditLetterConfirm do
  @moduledoc """
  What Email and Withdraw ask before they act on tax credit letters (#995), on the
  letters list and a letter's page: who gets what, named up to 3, then counted a line
  per group by what happens, with anyone not emailed on their own line
  (/styles/confirm-dialog#many). Each function gives a button's `data-confirm`
  attributes. A record is the letters list's: the member, their current `letter` or
  nil, `email`, what Email does for them (EmailTaxCreditLetters.what/1), and
  `total_minutes`.
  """

  import Web.Components.Messages, only: [confirm_check: 2, name_them?: 1]

  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.TaxCreditLetter
  alias App.Operation.EmailTaxCreditLetters
  alias Service.Format

  @doc "Email letters on the list, for the checked it reaches."
  def email(records, year) do
    {emailed, not_emailed} = Enum.split_with(records, &EmailTaxCreditLetters.emailed?(&1.member))
    count = length(emailed)

    {question, body, button} =
      if count > 0,
        do:
          {"Email #{letters(count, "tax credit letter")} for #{year}?",
           "Each member gets their latest letter as a PDF.", "Email #{letters(count)}"},
        else:
          {"Publish #{letters(length(not_emailed), "tax credit letter")} for #{year}?",
           "They have no email, so each goes on Your membership only.",
           "Publish #{letters(length(not_emailed))}"}

    lines =
      if name_them?(records),
        do: Enum.map(emailed, &line/1),
        else: groups(emailed)

    lines = if count > 0, do: lines ++ not_emailed_line(not_emailed), else: lines

    %{
      "data-confirm" => "#{question} #{body}",
      "data-confirm-list" => Jason.encode!(lines),
      "data-confirm-button" => button
    }
    |> Map.merge(cannot_take_back(count))
  end

  # From 10 emails, a send waits on a box naming the count.
  defp cannot_take_back(count) when count < 10, do: %{}

  defp cannot_take_back(count) do
    count
    |> confirm_check(
      "I understand #{Format.count(count, one: "%d member", many: "%d members")} get this email."
    )
    |> Map.put("data-confirm-warning", "Emails cannot be taken back.")
  end

  # One member's line, with what happens: "Cameron Ruiz, a new letter: 132h 30m replaces 117 hours".
  defp line(%{email: :first, member: member}), do: "#{member.name}, a new letter"

  defp line(%{email: :replace, member: member} = record) do
    case TaxCreditLetter.total_minutes(record.letter) do
      minutes when is_integer(minutes) and minutes != record.total_minutes ->
        "#{member.name}, a new letter: #{Format.duration(record.total_minutes)} replaces #{Format.duration(minutes)}"

      _same ->
        "#{member.name}, a new letter in place of one out of date"
    end
  end

  defp line(%{email: :failed, member: member}), do: "#{member.name}, the letter that did not send"

  defp line(%{email: :not_emailed, member: member}),
    do: "#{member.name}, their letter, never emailed before"

  defp line(%{email: :again, member: member}), do: "#{member.name}, their letter again"

  @groups [:first, :replace, :failed, :not_emailed, :again]

  # A counted line for each group, in order.
  defp groups(records) do
    counts = Enum.frequencies_by(records, & &1.email)
    for what <- @groups, count = counts[what], do: group(what, count)
  end

  defp group(:first, n),
    do: Format.count(n, one: "1 gets their first letter.", many: "%d get their first letter.")

  defp group(:replace, n),
    do:
      Format.count(n,
        one:
          "1 gets a new letter in place of one out of date. Their old letter will verify as Replaced.",
        many:
          "%d get a new letter in place of one out of date. Their old letters will verify as Replaced."
      )

  defp group(:failed, n),
    do:
      Format.count(n,
        one: "1 gets the letter that did not send.",
        many: "%d get the letter that did not send."
      )

  defp group(:not_emailed, n),
    do:
      Format.count(n,
        one: "1 gets their letter, never emailed before.",
        many: "%d get their letter, never emailed before."
      )

  defp group(:again, n),
    do: Format.count(n, one: "1 gets their letter again.", many: "%d get their letter again.")

  # Those Email publishes for with no email, named up to 3.
  defp not_emailed_line([]), do: []

  defp not_emailed_line([one]),
    do: ["Not emailed: #{one.member.name} has no email. The letter goes on Your membership only."]

  defp not_emailed_line(records) do
    who =
      if name_them?(records),
        do: names(records),
        else: length(records)

    ["Not emailed: #{who} have no email. Their letters go on Your membership only."]
  end

  @doc "Withdraw letters on the list, for the checked with one. The box waits from 1."
  def withdraw(records, year) do
    count = length(records)
    {emailed, never} = Enum.split_with(records, &(&1.letter.email_status == :sent))

    question =
      if name_them?(records),
        do:
          "Withdraw the #{year} #{if count == 1, do: "letter", else: "letters"} of #{names(records)}?",
        else: "Withdraw #{letters(count, "tax credit letter")} for #{year}?"

    body =
      if count == 1,
        do: "Nothing takes its place. They list under No letter again.",
        else: "Nothing takes their place. They list under No letter again."

    %{
      "data-confirm" => "#{question} #{body}",
      "data-confirm-check" =>
        Format.count(count,
          one: "I understand 1 letter no longer verifies.",
          many: "I understand %d letters no longer verify."
        ),
      "data-confirm-button" => "Withdraw #{letters(count)}"
    }
    |> Map.merge(withdraw_lines(name_them?(records), emailed, never))
  end

  # Up to 3, who has it by email; past that, a line each for those emailed and not.
  defp withdraw_lines(true, [], _never), do: %{}

  defp withdraw_lines(true, [one], _never),
    do: %{
      "data-confirm-warning" =>
        "#{one.member.name} has theirs by email. Its verify page will say Withdrawn."
    }

  defp withdraw_lines(true, emailed, _never),
    do: %{
      "data-confirm-warning" =>
        "#{names(emailed)} have theirs by email. Their verify pages will say Withdrawn."
    }

  defp withdraw_lines(false, emailed, never) do
    lines =
      Enum.reject(
        [
          emailed != [] &&
            Format.count(length(emailed),
              one: "1 was emailed. Its verify page will say Withdrawn.",
              many: "%d were emailed. Their verify pages will say Withdrawn."
            ),
          never_line(never)
        ],
        &(&1 in [false, nil])
      )

    %{"data-confirm-list" => Jason.encode!(lines)}
  end

  defp never_line([]), do: nil
  defp never_line([one]), do: "#{one.member.name}'s was never emailed."

  defp never_line(records) do
    if name_them?(records),
      do: "#{Format.and_list(Enum.map(records, &"#{&1.member.name}'s"))} were never emailed.",
      else: "#{length(records)} were never emailed."
  end

  @doc """
  Email letter on a letter's page, or Publish letter for a member with no email: what
  Email does for them, and what it replaces.
  """
  def email_one(%{member: member} = record) do
    if EmailTaxCreditLetters.emailed?(member) do
      %{
        "data-confirm" =>
          join("Email #{member.name}'s letter to #{member.email}?", email_body(record)),
        "data-confirm-button" => "Email letter"
      }
    else
      %{
        "data-confirm" =>
          join(
            "Publish #{member.name}'s letter?",
            "#{Member.first_name(member)} has no email, so it goes on Your membership only.#{replaced(record)}"
          ),
        "data-confirm-button" => "Publish letter"
      }
    end
  end

  defp email_body(%{email: :first} = record),
    do:
      "There is no letter yet, so one with #{Format.duration(record.total_minutes)} is published first."

  defp email_body(%{email: :replace} = record),
    do:
      "It is out of date, so a new letter with #{Format.duration(record.total_minutes)} is published first." <>
        replaced(record)

  defp email_body(%{email: :failed}), do: "The last email did not send."

  defp email_body(%{email: :again}),
    do: "It was emailed before, and goes again as it was published."

  defp email_body(_record), do: nil

  defp replaced(%{email: :replace}), do: " The old one then verifies as Replaced."
  defp replaced(_record), do: ""

  @doc "Withdraw letter on a letter's page: what's lost, and the box."
  def withdraw_one(%PublishedPDF{} = letter, %Member{} = member) do
    code = PublishedPDF.format_code(letter.code)
    first = Member.first_name(member)

    %{
      "data-confirm" =>
        "Withdraw #{member.name}'s letter #{code}? Nothing takes its place. #{first} lists under No letter again.",
      "data-confirm-check" => "I understand #{code} no longer verifies.",
      "data-confirm-button" => "Withdraw letter"
    }
    |> Map.merge(
      if letter.email_status == :sent,
        do: %{
          "data-confirm-warning" =>
            "#{first} has it by email. Its verify page will say Withdrawn."
        },
        else: %{}
    )
  end

  defp join(question, nil), do: question
  defp join(question, body), do: "#{question} #{body}"

  defp names(records), do: records |> Enum.map(& &1.member.name) |> Format.and_list()

  defp letters(n, noun \\ "letter"), do: Format.count(n, one: "%d #{noun}", many: "%d #{noun}s")
end
