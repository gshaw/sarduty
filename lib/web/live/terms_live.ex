defmodule Web.TermsLive do
  use Web, :live_view_marketing_layout

  # Kept short and general on purpose, like Web.PrivacyLive.
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Terms")}
  end

  def render(assigns) do
    ~H"""
    <article id="terms" class="max-w-prose">
      <h1 class="title">Terms</h1>
      <p class="hint">Last changed October 7, 2026.</p>
      <p>
        You use SAR Duty for your team. You must be allowed to give SAR Duty your team's D4H access key.
      </p>
      <p>
        Your team is responsible for its data and for the changes SAR Duty makes in D4H for you. Check each tax credit letter before a member uses it.
      </p>
      <p>
        SAR Duty is provided as is, with no warranty. It can change or stop at any time. Keep D4H as your system of record.
      </p>
      <p>
        As far as the law allows, SAR Duty is not liable for lost data, wrong letters, or time it is not available.
      </p>
      <p>
        Your team can stop using SAR Duty at any time. SAR Duty can suspend a team that misuses it.
      </p>
      <p>
        These terms can change. The date above shows the last change. The laws of British Columbia and Canada apply.
      </p>
      <p>
        <.a id="terms-privacy" navigate={~p"/privacy"}>Privacy</.a>
      </p>
    </article>
    """
  end
end
