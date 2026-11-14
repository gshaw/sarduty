defmodule Web.FieldText do
  @moduledoc """
  Words about a custom field's records (#1056): the noun for one record of its kind, and
  how many hold an answer. Change field's lead and the field page's Delete field say it
  the same way.
  """

  @doc "One record of a field's kind, as a sentence names it."
  def noun("incident"), do: "incident"
  def noun("exercise"), do: "exercise"
  def noun("event"), do: "event"
  def noun("member"), do: "member"
  def noun("team"), do: "team"
  def noun(_equipment), do: "item"

  @doc "How many records of `target` hold an answer. The team is one record."
  def answers("team", 0), do: "The team has no answer."
  def answers("team", _count), do: "The team has an answer."
  def answers(target, 0), do: "No #{noun(target)} has an answer."

  def answers(target, count),
    do:
      Service.Format.count(count,
        one: "1 #{noun(target)} has an answer.",
        many: "%d #{noun(target)}s have an answer."
      )
end
