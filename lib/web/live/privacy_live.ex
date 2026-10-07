defmodule Web.PrivacyLive do
  use Web, :live_view_marketing_layout

  # Doesn't receive mail until sarduty.com has an inbox or Email Routing for it.
  @contact "privacy@sarduty.com"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Privacy", contact: @contact)}
  end

  def render(assigns) do
    ~H"""
    <article id="privacy" class="max-w-prose">
      <h1 class="title">Privacy</h1>
      <p class="lead">
        SAR Duty holds your team's D4H data to run its tools. It does not sell it, show ads, or track you.
      </p>
      <p class="hint">Last changed October 7, 2026.</p>

      <h2 class="heading">Who runs SAR Duty</h2>
      <p>
        Gerry Shaw runs SAR Duty in Canada. Each team decides what goes into D4H. SAR Duty copies it and works on it for the team.
      </p>

      <h2 class="heading">What SAR Duty holds</h2>
      <ul class="list paragraph">
        <li>
          Members, from D4H: name, email, phone, home address, photo, position, attendance, qualifications, and groups.
        </li>
        <li>Tax credit letters: the member's name, address, and hours.</li>
        <li>Accounts: the email and phone number you log in with.</li>
        <li>
          Logins: when you log in, your IP address, and your browser. SAR Duty deletes these after 90 days.
        </li>
        <li>
          Changes to who can reach a team, and letters sent. SAR Duty keeps these 2 years as a record.
        </li>
      </ul>

      <h2 class="heading">Cookies</h2>
      <p>
        SAR Duty sets 2 cookies: one keeps you logged in for 60 days, and one remembers that this browser has logged in before. There are no analytics or advertising cookies.
      </p>

      <h2 class="heading">Who else sees it</h2>
      <p>SAR Duty uses these services to do its work. Some are in the United States.</p>
      <ul class="list paragraph">
        <li>Fly.io hosts SAR Duty in Toronto.</li>
        <li>Cloudflare sends email and stores encrypted backups.</li>
        <li>Twilio texts login codes, if you log in by text.</li>
        <li>Mapbox gets home addresses to work out driving distances for mileage reports.</li>
        <li>Apple and Google hold ID cards that members add to their Wallet.</li>
        <li>Honeybadger gets error reports, with keys and codes removed.</li>
      </ul>
      <p>
        Anyone with an ID card's code can see the member's name, photo, and team at the verify site. Anyone with a tax credit letter's reference can check the letter is real.
      </p>

      <h2 class="heading">How long SAR Duty keeps it</h2>
      <p>
        Member data stays while the team uses SAR Duty. Each refresh copies changes from D4H. When a team stops using SAR Duty, its data is deleted on request.
      </p>

      <h2 class="heading">Your data</h2>
      <p>
        To see, fix, or remove your member data, ask your team. Most of it comes from D4H, so the change is made there. For anything else, email <.a
          id="privacy-contact"
          href={"mailto:" <> @contact}
        >{@contact}</.a>.
      </p>
    </article>
    """
  end
end
