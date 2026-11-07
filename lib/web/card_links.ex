defmodule Web.CardLinks do
  @moduledoc """
  The signed link an ID card's email holds (#952), to `/cards/:token`: the card's page,
  with no login, where the member adds it to Apple or Google Wallet. The token names one
  card and is the only access, so the page and its two pass routes do nothing else. It
  stops giving a pass once the card is replaced, cancelled, or not active
  (`MemberCard.link_status/2`).
  """
  alias App.Model.MemberCard

  @salt "member card"

  # As long as the reminders link: members keep the email, and a card lasts for years.
  @max_age 5 * 365 * 24 * 60 * 60

  def path(%MemberCard{id: id}), do: "/cards/" <> Phoenix.Token.sign(Web.Endpoint, @salt, id)

  def url(%MemberCard{} = card), do: Web.Endpoint.url() <> path(card)

  @doc """
  The card a token names, with `member: [team: :organization]`. Nil for a token that is
  bad or too old, or a card that is gone.
  """
  def find_card(token) when is_binary(token) do
    case Phoenix.Token.verify(Web.Endpoint, @salt, token, max_age: @max_age) do
      {:ok, card_id} when is_integer(card_id) -> MemberCard.get_with_member(card_id)
      _error -> nil
    end
  end
end
