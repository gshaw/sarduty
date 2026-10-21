defmodule Service.ChoreEventText do
  @moduledoc """
  The title and description of a chore event in D4H (#341). Pure: chores in, text out.
  D4H keeps p, b, i, and lists in a description but strips tables, so each member is a
  paragraph and a list. Every member-written string is escaped.
  """

  alias Service.Format

  @doc ~s(The event's title: "Chores: Equipment maintenance, October 2026".)
  def title(category_title, %Date{} = month),
    do: "Chores: #{category_title}, #{Format.month_year_long(month)}"

  @doc """
  The event's description: a note that SAR Duty made it, each member's chores by date
  with their total, members by name, and a line of totals. `chores` have their members.
  """
  def description(chores) do
    members =
      chores
      |> Enum.group_by(& &1.member)
      |> Enum.sort_by(fn {member, _chores} -> {String.downcase(member.name), member.id} end)

    minutes = chores |> Enum.map(& &1.minutes) |> Enum.sum()

    IO.iodata_to_binary([
      "<p><i>Made by SAR Duty from accepted chores. Change them in SAR Duty: edits here are replaced.</i></p>",
      Enum.map(members, &member_html/1),
      "<p>",
      escape(
        Enum.join(
          [
            Format.count(length(members), one: "1 member", many: "%d members"),
            Format.count(length(chores), one: "1 chore", many: "%d chores"),
            Format.duration(minutes)
          ],
          ", "
        )
      ),
      ".</p>"
    ])
  end

  defp member_html({member, chores}) do
    chores = chores |> Enum.sort_by(& &1.id) |> Enum.sort_by(& &1.date, Date)
    total = chores |> Enum.map(& &1.minutes) |> Enum.sum()

    [
      "<p><b>",
      escape(member.name),
      "</b>: ",
      escape(Format.duration(total)),
      "</p><ul>",
      Enum.map(chores, fn chore ->
        [
          "<li>",
          escape("#{Format.day_in_year(chore.date, chore.date)}: #{chore.description}, "),
          escape(Format.duration(chore.minutes)),
          "</li>"
        ]
      end),
      "</ul>"
    ]
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
