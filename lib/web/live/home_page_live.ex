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

    {:ok, assign(socket, page_title: "Less paperwork for search and rescue teams", teams: teams)}
  end

  def render(assigns) do
    ~H"""
    <div class="home">
      <section class="home-hero">
        <div class="home-wrap home-hero-split">
          <div>
            <h1 id="home-title">Less paperwork for search and rescue teams</h1>
            <p class="home-lead">
              SAR Duty works from your team's D4H data. It does the jobs D4H does not, so team
              admins spend less time at a desk.
            </p>
            <%= if @current_user do %>
              <ul :if={@teams != []} id="my-teams" class="home-teams">
                <li :for={team <- @teams}>
                  <.button navigate={~p"/teams/#{team}"} variant={:primary}>{team.name}</.button>
                </li>
              </ul>
              <p :if={@teams == []} id="no-teams">
                Your email is not an Owner or Editor on any team SAR Duty knows. Access comes from
                D4H: check the email D4H has for you, or ask one of your team's D4H owners.
              </p>
            <% else %>
              <.cta />
              <p class="home-note">For teams that keep their records in D4H.</p>
            <% end %>
          </div>
          <HomeMockups.team_home />
        </div>
      </section>

      <section class="home-section">
        <div class="home-wrap">
          <div class="home-feature">
            <div>
              <h2>Tax credit letters</h2>
              <p>
                Make each member's tax credit letter from their D4H attendance, and email it to them.
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
              <p>Record who arrives and leaves on a phone, then send the attendance to D4H.</p>
            </div>
            <HomeMockups.door />
          </div>
        </div>
      </section>

      <section :if={!@current_user} class="home-section is-alt">
        <div class="home-wrap home-start">
          <div>
            <h2>Try it with your team</h2>
            <p>You need Owner or Editor access to your team in D4H, and a D4H access key.</p>
          </div>
          <.cta />
        </div>
      </section>
    </div>
    """
  end

  defp cta(assigns) do
    ~H"""
    <div class="home-cta">
      <.button navigate={~p"/signup"} variant={:primary}>Sign up a team</.button>
      <.button navigate={~p"/login"}>Log in</.button>
    </div>
    """
  end
end
