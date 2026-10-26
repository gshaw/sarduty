defmodule Web.HomePageLive do
  use Web, :live_view_marketing_layout

  alias App.Model.Team
  alias Web.Components.HomeMockups

  # The page has 3 readers: a team admin deciding whether to sign up, someone verifying a
  # tax credit letter (the CRA), and a reviewer checking who issues the Wallet passes
  # (Google). The app changes fast, so the copy says what each feature is for, not how it
  # works. The pictures are made up.

  def mount(_params, _session, socket) do
    teams =
      case socket.assigns.current_user do
        nil -> []
        user -> Team.get_managed_by(user.email, DateTime.utc_now())
      end

    {:ok,
     assign(socket,
       page_title: "Less paperwork for search and rescue teams",
       teams: teams,
       members: socket.assigns[:member_logins] || []
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="home">
      <section class="home-hero">
        <div class="home-wrap home-hero-split">
          <div>
            <h1 id="home-title">Less paperwork for search and rescue teams</h1>
            <p class="home-lead">
              SAR Duty builds on your team's D4H records with tools made for volunteer teams: tax
              credit letters, ID cards on members' phones, attendance at the door, and more.
            </p>
            <.start id="start-top" current_user={@current_user} teams={@teams} members={@members} />
          </div>
          <figure class="home-hero-art">
            <HomeMockups.team_home />
            <figcaption>A sample team</figcaption>
          </figure>
        </div>
      </section>

      <section class="home-section">
        <div class="home-wrap">
          <div class="home-feature">
            <div>
              <h2>Tax credit letters</h2>
              <p>
                Make each member's tax credit letter from the hours they gave, and email it to them.
              </p>
              <p>
                Anyone can verify a letter at <a href={Web.VerifyHost.url() <> "/letters"}>verify.sarduty.com/letters</a>, so the
                CRA knows the hours are real.
              </p>
            </div>
            <HomeMockups.letter />
          </div>
          <div class="home-feature is-flipped">
            <div>
              <h2>ID cards on members' phones</h2>
              <p>
                Each team issues ID cards to its own members, who carry them in Apple Wallet or
                Google Wallet. Anyone can verify a card by scanning its QR code.
              </p>
            </div>
            <HomeMockups.id_card />
          </div>
          <div class="home-feature">
            <div>
              <h2>Attendance at the door</h2>
              <p>
                Scan members as they arrive and leave, on a phone or an iPad at the hall. A team
                admin checks the attendance and sends it in one step.
              </p>
            </div>
            <HomeMockups.door />
          </div>
        </div>
      </section>

      <section class="home-section is-alt" id="home-more">
        <div class="home-wrap">
          <h2>Everything a team admin keeps track of</h2>
          <ul class="home-grid">
            <li :for={{title, text} <- more()}>
              <h3>{title}</h3>
              <p>{text}</p>
            </li>
          </ul>
        </div>
      </section>

      <section class="home-section" id="home-coming">
        <div class="home-wrap home-measure">
          <h2>In active development</h2>
          <p class="home-lead">
            SAR Duty grows with the teams that use it. To get involved, email Andrew Wallwork or
            Gerry Shaw at <a href="mailto:support@sarduty.com">support@sarduty.com</a>.
          </p>
          <p class="home-lead">
            The code is open: <a href="https://github.com/gshaw/sarduty">SAR Duty on GitHub</a>.
          </p>
        </div>
      </section>

      <section class="home-section is-alt">
        <div class="home-wrap home-end">
          <.start id="start-end" current_user={@current_user} teams={@teams} members={@members} />
        </div>
      </section>
    </div>
    """
  end

  # What has shipped, beyond the 3 pictures above. One line each, for what the reader gets.
  defp more do
    [
      {"Activities and replies",
       "Add exercises and events, put members on them, and see who signed up. Members reply from the email without logging in."},
      {"Members",
       "See each member's standing, hours, and last activity. Find who has not attended in a while."},
      {"Groups",
       "Write rules from qualifications and standing, then add or remove the members who fit them."},
      {"Qualifications and certificates",
       "See which awards expire soon. Members send in a certificate, and a team admin accepts it."},
      {"Equipment",
       "Know who holds each item, scan kits onto an activity, and see what retired members still hold."},
      {"Chores",
       "Members log the time they give outside activities, such as fixing a truck. It counts toward their tax credit letter."},
      {"Mileage report",
       "Driving distances from each member's home to an activity, worked out for you."},
      {"Your membership",
       "Each member sees their year: their hours, their qualifications, their ID card, and what they signed up for."},
      {"Change history", "SAR Duty keeps a history of every change to a member or an activity."}
    ]
  end

  attr :id, :string, required: true
  attr :current_user, :map, default: nil
  attr :teams, :list, required: true
  attr :members, :list, required: true

  # The page's one call to action, the same box in the same places for everyone: sign up or
  # log in for a visitor, your teams once logged in, your own ID card for a member, or why
  # you have none.
  defp start(assigns) do
    ~H"""
    <div id={@id} class="home-start">
      <%= cond do %>
        <% @current_user == nil -> %>
          <p class="home-start-title">Start with your team</p>
          <p>
            Sign up with your team's D4H access key. You need Owner or Editor access in D4H.
          </p>
          <div class="home-cta">
            <.button navigate={~p"/signup"} variant={:primary}>Sign up a team</.button>
            <.button navigate={~p"/login"}>Log in</.button>
          </div>
        <% @teams != [] -> %>
          <p class="home-start-title">Your teams</p>
          <ul class="home-cta">
            <li :for={team <- @teams}>
              <.button navigate={~p"/teams/#{team}"} variant={:primary}>{team.name}</.button>
            </li>
          </ul>
        <% @members != [] -> %>
          <p class="home-start-title">Your ID card</p>
          <ul class="home-cta">
            <li :for={member <- @members}>
              <.button navigate={~p"/teams/#{member.team}/me"} variant={:primary}>
                {member.team.name}
              </.button>
            </li>
          </ul>
        <% true -> %>
          <p class="home-start-title">You are not on a team yet</p>
          <p>
            Your email is not an Owner or Editor on any team SAR Duty knows. Check the email D4H
            has for you, or ask an Owner of your team in D4H.
          </p>
          <div class="home-cta">
            <.button navigate={~p"/signup"} variant={:primary}>Sign up a team</.button>
          </div>
      <% end %>
    </div>
    """
  end
end
