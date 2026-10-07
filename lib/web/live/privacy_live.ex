defmodule Web.PrivacyLive do
  use Web, :live_view_marketing_layout

  # Kept short and general on purpose, so it holds while features change. Update the date
  # when the meaning changes.
  @contact "privacy@sarduty.com"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Privacy", contact: @contact)}
  end

  def render(assigns) do
    ~H"""
    <article id="privacy" class="max-w-prose">
      <h1 class="title">Privacy</h1>
      <p class="hint">Last changed October 7, 2026.</p>
      <p>
        SAR Duty copies your team's data from D4H to run its tools for your team. Your team decides what is in D4H.
      </p>
      <p>
        SAR Duty also keeps the email or phone number you log in with. It keeps records of each login, with the IP address, for 90 days.
      </p>
      <p>
        Anyone with a member's ID card code can see the member's name, photo, and team on the verify site.
      </p>
      <p>
        SAR Duty does not sell data, show ads, or use tracking cookies. Its cookies keep you logged in.
      </p>
      <p>
        Service providers host SAR Duty, send its email and texts, and store its backups. Some are in the United States. Each gets only what its work needs.
      </p>
      <p>
        To see, fix, or remove your data, ask your team. Most of it comes from D4H, so the change is made there. For anything else, email <.a
          id="privacy-contact"
          href={"mailto:" <> @contact}
        >{@contact}</.a>.
      </p>
    </article>
    """
  end
end
