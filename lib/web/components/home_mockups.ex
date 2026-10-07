defmodule Web.Components.HomeMockups do
  @moduledoc """
  Pictures of SAR Duty for the public home page, drawn in HTML so they follow light and
  dark. Everything in them is made up: the team, the members, the hours, and the codes.
  Each carries a Sample mark, and the QR codes read "SAMPLE" and open nothing.
  """
  use Phoenix.Component

  alias Web.Components.Core

  # cspell:ignore viewbox Okafor Nakamura Dhillon Moreau Larsen SAMP — made-up names, and the
  # sample ID card code SAMP-LE00

  @qr "SAMPLE" |> EQRCode.encode(:m) |> EQRCode.svg(viewbox: true, color: "#000")

  @team "Coast Range SAR"

  defp sample(assigns) do
    ~H"""
    <span class="home-sample">Sample</span>
    """
  end

  defp qr(assigns) do
    assigns = assign(assigns, :svg, @qr)

    ~H"""
    <span class="home-qr" aria-hidden="true">{Phoenix.HTML.raw(@svg)}</span>
    """
  end

  defp logo(assigns) do
    ~H"""
    <span class="home-logo" aria-hidden="true">CR</span>
    """
  end

  @doc "A team's home page in a browser window."
  def team_home(assigns) do
    assigns =
      assign(assigns,
        team: @team,
        coming_up: [
          {"Wed Oct 7", "19:10", :exercise, "Rope rescue, Elfin Lakes"},
          {"Fri Oct 9", "15:50", :incident, "Lost snowshoers, Britannia Beach"},
          {"Sat Oct 10", "09:10", :exercise, "Swiftwater refresher, Elfin Lakes"},
          {"Sat Oct 17", "09:00", :exercise, "First aid scenarios, Alice Lake"}
        ],
        attention: [
          {:warning, "2 activities to check", "Still drafts in D4H, so attendance can change."},
          {:warning, "7 qualifications expire in 60 days", "Rope rescue, first aid, and 2 more."},
          {:info, "11 tax credit letters to create", "41 of 52 done."}
        ]
      )

    ~H"""
    <figure class="home-browser" aria-label="A sample team's home page">
      <div class="home-browser-bar" aria-hidden="true">
        <i></i><i></i><i></i><span>sarduty.com/teams/coastrange</span>
      </div>
      <div class="home-app-bar">
        <span class="brand">SAR <span>Duty</span></span>
        <span class="is-current">Home</span>
        <span>Activities</span>
        <span class="home-hide-sm">Members</span>
        <span class="home-hide-sm">Qualifications</span>
      </div>
      <div class="home-app-body">
        <div class="home-team-head">
          <.logo />
          <div>
            <strong>{@team}</strong>
            <span>Refreshed from D4H 7 min ago</span>
          </div>
        </div>
        <div class="home-next-up">
          <div>
            <span class="home-caps">Next up</span>
            <strong>Wed Oct 7</strong>
            <strong class="home-big">19:10</strong>
          </div>
          <div>
            <Core.badge kind={:exercise}>Exercise</Core.badge>
            <strong>Rope rescue, Elfin Lakes</strong>
            <span class="home-muted">Today</span>
          </div>
          <span class="home-fake-btn is-primary home-hide-sm">Take attendance</span>
        </div>
        <div class="home-app-cols">
          <div class="home-panel">
            <strong>Coming up</strong>
            <ul>
              <li :for={{day, time, kind, title} <- @coming_up}>
                <span class="home-when"><b>{day}</b> {time}</span>
                <i class={"home-dot is-#{kind}"}></i>
                <span class="home-link">{title}</span>
              </li>
            </ul>
          </div>
          <div class="home-panel home-hide-sm">
            <strong>Needs attention</strong>
            <ul>
              <li :for={{level, title, why} <- @attention}>
                <i class={"home-dot is-#{level}"}></i>
                <span><b>{title}</b><br /><span class="home-muted">{why}</span></span>
              </li>
            </ul>
          </div>
        </div>
      </div>
      <.sample />
    </figure>
    """
  end

  @doc "A tax credit letter, laid out like the PDF."
  def letter(assigns) do
    assigns = assign(assigns, team: @team)

    ~H"""
    <figure class="home-letter" aria-label="A sample tax credit letter">
      <div class="home-letter-head">
        <.logo />
        <div><strong>{@team}</strong><span>PO Box 100, Squamish BC</span></div>
      </div>
      <p>To whom it may concern:</p>
      <p>Name: Avery Chen<br />Address: 12 Sample Street, Squamish BC</p>
      <p>
        This letter serves to confirm that the above noted individual has completed eligible
        volunteer search and rescue hours for {@team} in the 2025 calendar year.
      </p>
      <p class="home-letter-hours">
        Primary hours: 212 hours 30 minutes<br /> Secondary hours: 48 hours 15 minutes<br />
        Total hours: 260 hours 45 minutes
      </p>
      <div class="home-letter-foot">
        <div>
          <span class="home-signature">Jordan Larsen</span>
          <span>Jordan Larsen, Training Officer</span>
          <span class="home-mono">Reference: SRVTC-SAMPLE00</span>
          <span class="home-mono">Verify this letter at verify.sarduty.com/letters</span>
        </div>
        <.qr />
      </div>
      <.sample />
    </figure>
    """
  end

  @doc "A member's ID card in a Wallet app."
  def id_card(assigns) do
    assigns = assign(assigns, team: @team)

    ~H"""
    <figure class="home-pass" aria-label="A sample ID card">
      <div class="home-pass-top">
        <.logo />
        <strong>{@team}</strong>
      </div>
      <div class="home-pass-main">
        <div>
          <span class="home-pass-label">Member</span>
          <span class="home-pass-name">Avery Chen</span>
          <span class="home-pass-label">Status</span>
          <span>Active</span>
        </div>
        <span class="home-photo" aria-hidden="true">AC</span>
      </div>
      <div class="home-pass-qr">
        <.qr />
        <span>SAMP-LE00</span>
      </div>
      <.sample />
    </figure>
    """
  end

  @doc "Taking attendance at the door, on a phone."
  def door(assigns) do
    assigns =
      assign(assigns,
        rows: [
          {"18:58", "Avery Chen"},
          {"18:57", "Riley Okafor"},
          {"18:55", "Morgan Nakamura"},
          {"18:52", "Sasha Dhillon"},
          {"18:50", "Quinn Moreau"}
        ]
      )

    ~H"""
    <figure class="home-phone" aria-label="A sample attendance page on a phone">
      <div class="home-phone-screen">
        <span class="home-caps">Exercise · 19:00</span>
        <strong class="home-door-title">Rope rescue night</strong>
        <div class="home-door-modes" aria-hidden="true">
          <span class="is-current">Arriving</span><span>Leaving</span>
        </div>
        <div class="home-door-scan" aria-hidden="true"><i></i></div>
        <ul>
          <li :for={{time, name} <- @rows}>
            <span>{name}</span><span class="home-muted">Arrived {time}</span>
          </li>
        </ul>
      </div>
      <.sample />
    </figure>
    """
  end
end
