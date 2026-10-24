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
      <p class="hint">Last changed October 23, 2026.</p>
      <p>
        SAR Duty copies your team's data from D4H to run its tools for your team. Your team decides what is in D4H.
      </p>
      <p>
        Your team is responsible for its members' data. SAR Duty handles that data for your team as a service provider.
      </p>
      <p>
        SAR Duty also keeps the email or phone number you log in with. It keeps records of each login, with the IP address, for 90 days.
      </p>
      <p id="privacy-certificates">
        SAR Duty keeps a certificate a member sends only until a team admin accepts or declines it.
      </p>
      <p>
        Anyone with a member's ID card code can see the member's name, photo, and team on the verify site.
      </p>
      <p id="privacy-members">
        On a team with member logins on, members see each other's roster, attendance, groups, and qualifications. Phone numbers, addresses, emails, and emergency contacts stay with team admins.
      </p>
      <p>
        SAR Duty does not sell data, show ads, or use tracking cookies. Its cookies keep you logged in.
      </p>
      <p>
        SAR Duty's server and database are in Canada. The other services it uses can be anywhere, and get only what they need.
      </p>
      <p id="privacy-operator">
        Gerry Shaw, a volunteer member of South Fraser Search and Rescue, runs SAR Duty. SAR Duty is an independent project. South Fraser Search and Rescue and the other teams that use it do not run, own, or endorse it.
      </p>
      <p id="privacy-access">
        SAR Duty's admins can see every team's data in SAR Duty. There are 2 today: Gerry Shaw and Andrew Wallwork. They look at team data only to run, fix, support, secure, or improve SAR Duty, or to look into a security problem, misuse, or failure. They share it only when the law requires it. SAR Duty does not use team data for anything else.
      </p>
      <p id="privacy-organizations">
        When a team belongs to an organization, its organization admins, such as an association's staff, see each of its teams' totals, never members' names or contact details.
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
