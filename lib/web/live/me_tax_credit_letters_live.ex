defmodule Web.MeTaxCreditLettersLive do
  use Web, :live_view_app_layout

  alias App.Model.TaxCreditLetter

  # Every year's tax credit letter for the member, /teams/:subdomain/me/tax-credit-letters.
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Tax credit letters")
      |> assign(:letters, TaxCreditLetter.get_all_for_member(socket.assigns.member))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="measure">
      <h1 class="title">Tax credit letters</h1>
      <.empty_state :if={@letters == []} id="no-letters" title="No tax credit letters yet">
        Your team admins make them after each year ends.
      </.empty_state>
      <ul :if={@letters != []} id="letters" class="flex flex-col gap-4">
        <li :for={letter <- @letters} id={"letter-#{letter.id}"}>
          <.button href={~p"/teams/#{@member.team}/me/tax-credit-letters/#{letter.id}/pdf"}>
            Download {letter.year} letter
          </.button>
          <span class="hint block mt-1">
            Made {Service.Format.date_long(letter.inserted_at, @member.team.timezone)}
          </span>
        </li>
      </ul>
    </div>
    """
  end
end
