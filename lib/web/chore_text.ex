defmodule Web.ChoreText do
  @moduledoc """
  The words and tags for chores (#341), so the member's pages and the team admin's say
  the same thing. Accepted is the normal state and has no tag.
  """

  use Phoenix.Component

  import Web.Components.Core, only: [badge: 1, input: 1]

  alias Service.Format

  attr :chore, :map, required: true
  attr :id, :string, default: nil

  @doc "Waiting is a grey tag, Declined an amber one, and Accepted none."
  def status_badge(assigns) do
    ~H"""
    <.badge :if={@chore.status == :waiting} id={@id}>Waiting</.badge>
    <.badge :if={@chore.status == :declined} id={@id} kind={:warning}>Declined</.badge>
    """
  end

  attr :checked, :boolean, required: true

  @doc """
  The box a team admin selects to accept their own chores (#697), on the Chores page and a
  chore's own page. Accept stays off until it is selected.
  """
  def own_box(assigns) do
    ~H"""
    <.input
      type="checkbox"
      id="accept-own"
      name="own"
      value={@checked}
      label="Accept my own chores"
    >
      I know another team admin should accept the chores I log. I'm making an exception.
    </.input>
    """
  end

  @doc "The flash when a team admin's own chores go to accept without the box checked."
  def own_refused, do: "Select Accept my own chores to accept yours."

  @doc ~s(A month's minutes by status: "7 hours accepted, 1 hour waiting".)
  def summary(totals) do
    [accepted: "accepted", waiting: "waiting", declined: "declined"]
    |> Enum.filter(fn {status, _word} -> totals[status] > 0 end)
    |> Enum.map_join(", ", fn {status, word} -> "#{Format.duration(totals[status])} #{word}" end)
  end

  @doc ~s(Why it was declined: "Declined Oct 2, 2026: “Log the generator check.”")
  def declined(chore, timezone),
    do: "Declined #{Format.date_short(chore.decided_at, timezone)}: “#{chore.decline_reason}”"

  @doc """
  The flash after a team admin's change and the send it set off
  (App.Operation.SendChores), as `{kind, text}`. `done` says what changed, such as
  "Accepted 3 chores", or is nil for Send changes.
  """
  def send_flash(done, %{events: events, failed: failed}) do
    {kind, result} =
      cond do
        failed > 0 ->
          {:error,
           Format.count(failed,
             one: "1 activity did not go through.",
             many: "%d activities did not go through."
           )}

        events > 0 or is_nil(done) ->
          {:info, "Chore activities are up to date."}

        true ->
          {:info, nil}
      end

    {kind, [done && "#{done}.", result] |> Enum.reject(&is_nil/1) |> Enum.join(" ")}
  end
end
