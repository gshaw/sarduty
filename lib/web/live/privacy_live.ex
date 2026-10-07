defmodule Web.PrivacyLive do
  use Web, :live_view_marketing_layout

  # A placeholder until the real text is written. It lists what the page must cover.

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Privacy")}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-2 pt-p2 pb-p2">
      <h1 id="privacy-title" class="title">Privacy</h1>
      <p id="privacy-placeholder">
        <.badge kind={:warning}>Placeholder</.badge>
        The full text is not written yet. It will cover:
      </p>
      <ul class="list mb-p">
        <li>What SAR Duty copies from D4H: members, attendance, qualifications, and groups.</li>
        <li>What it adds: tax credit letters, ID cards, and member photos on ID cards.</li>
        <li>Who can see it: team admins, and anyone verifying a letter or ID card.</li>
        <li>What a verify page shows about a member, and what it leaves out.</li>
        <li>Apple Wallet and Google Wallet: what an ID card holds, and how it changes.</li>
        <li>Where the data is stored, how long it is kept, and how to have it deleted.</li>
        <li>Email and text messages, and who sends them.</li>
        <li>Who to contact about your data.</li>
      </ul>
    </div>
    """
  end
end
