defmodule Web.TermsLive do
  use Web, :live_view_marketing_layout

  # A placeholder until the real text is written. It lists what the page must cover.

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Terms of use")}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-2 pt-p2 pb-p2">
      <h1 id="terms-title" class="title">Terms of use</h1>
      <p id="terms-placeholder">
        <.badge kind={:warning}>Placeholder</.badge>
        The full text is not written yet. It will cover:
      </p>
      <ul class="list mb-p">
        <li>Who may use SAR Duty, and who can sign up a team.</li>
        <li>What a team admin agrees to when they connect D4H.</li>
        <li>What SAR Duty changes in D4H, and that the team stays responsible for its records.</li>
        <li>Cost, if any, and how a team leaves.</li>
        <li>Who runs SAR Duty, and how to reach them.</li>
      </ul>
    </div>
    """
  end
end
