defmodule Web.Components.MemberLetter do
  @moduledoc """
  A member's tax credit letter for one year (#406), on Your membership and the year page:
  the year, its primary and secondary hours, and Download letter. With no letter yet for
  the current year, says when it comes.
  """

  use Web, :function_component

  alias App.Model.TaxCreditLetter
  alias Service.Format

  attr :id, :string, required: true
  attr :team, :map, required: true
  attr :letter, :map, default: nil, doc: "nil for a year with no letter yet"
  attr :year, :integer, required: true
  attr :hours, :boolean, default: true, doc: "false for the download alone"

  def member_letter(%{letter: nil} = assigns) do
    ~H"""
    <div id={@id}>
      <h2 class="chart-title mb-1">{@year} tax credit letter</h2>
      <p class="hint mb-0">Ready once a team admin makes it, after the year ends.</p>
    </div>
    """
  end

  def member_letter(assigns) do
    # An old letter that kept no hours has none to show.
    assigns = assign(assigns, :minutes, TaxCreditLetter.minutes(assigns.letter))

    ~H"""
    <div id={@id}>
      <h2 class="chart-title mb-1">{@year} tax credit letter</h2>
      <p class="hint mb-2">For your {@year} tax return.</p>
      <dl :if={@hours and @minutes != nil} class="dl-pairs">
        <dt>Primary hours</dt>
        <dd>{Format.duration(elem(@minutes, 0))}</dd>
        <dt>Secondary hours</dt>
        <dd>{Format.duration(elem(@minutes, 1))}</dd>
      </dl>
      <.button
        id={"#{@id}-download"}
        href={~p"/teams/#{@team}/me/tax-credit-letters/#{@letter.id}/pdf"}
      >
        Download letter
      </.button>
    </div>
    """
  end
end
