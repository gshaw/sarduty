defmodule Web.VerifySamplesLive do
  use Web, :live_view_verify_layout

  alias App.CoastRange
  alias App.Model.MemberCard

  # Public, on the verify site, at /samples (#854): a QR code for each answer the check
  # gives, for demos and docs. The cards are Coast Range SAR's (App.CoastRange), made up
  # and looked up in App.SampleRepo only, so their codes never change. "samples" has an
  # L, which card codes never do.
  #
  # The forged card's QR links to `.example`, a domain nobody can register.
  @forged_host "verify.sarduty.example"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sample ID cards", samples: samples())}
  end

  defp samples do
    verify_url = Web.VerifyHost.url()
    by_status = Map.new(CoastRange.sample_cards(), &{&1.status, &1.code})

    [
      %{
        id: "active",
        title: "Active member",
        text: "Cameron Ruiz, a current member. Shows the photo, team, and endorsements.",
        code: by_status.active
      },
      %{
        id: "inactive",
        title: "Not an active member",
        text: "Robin Tse, who retired. Shows the name and team, with no photo.",
        code: by_status.inactive
      },
      %{
        id: "revoked",
        title: "This card was cancelled",
        text: "Cameron's old card, replaced by the active one. Shows nothing about the member.",
        code: by_status.revoked
      },
      %{
        id: "not-found",
        title: "No card has this code",
        text: "A code no card has, as a typo or a made-up card gives.",
        code: by_status.not_found
      },
      %{
        id: "other-site",
        title: "Not a SAR Duty card",
        text:
          "A forged card. Its QR code links to #{@forged_host}, not #{Web.VerifyHost.host()}.",
        code: nil,
        qr: MemberCard.qr_url(by_status.active, "https://#{@forged_host}")
      }
    ]
    |> Enum.map(fn sample ->
      qr = sample[:qr] || (sample.code && MemberCard.qr_url(sample.code, verify_url))
      Map.merge(sample, %{qr: qr, svg: qr_svg(qr)})
    end)
  end

  defp qr_svg(text), do: text |> EQRCode.encode(:m) |> EQRCode.svg(viewbox: true, color: "#000")

  # A sample's own page, or for the forged card, the check of its link.
  defp check_path(%{code: code}) when is_binary(code), do: ~p"/#{MemberCard.format_code(code)}"
  defp check_path(%{qr: qr}), do: ~p"/?#{[code: qr]}"

  def render(assigns) do
    ~H"""
    <div id="samples">
      <h1 class="heading">Sample ID cards</h1>
      <p class="text-text-muted">
        Scan these to see each answer the check gives. They belong to Coast Range SAR, a
        made-up team, and every result says it is a sample. Their codes never change.
      </p>

      <div :for={sample <- @samples} id={"sample-#{sample.id}"} class="card mt-4">
        <div class="media items-start">
          <div class="qr-code qr-code-sm" aria-hidden="true">{raw(sample.svg)}</div>
          <div>
            <h2 class="subheading mb-0">{sample.title}</h2>
            <p class="text-sm">{sample.text}</p>
            <p :if={sample.code} class="font-mono mb-0">{MemberCard.format_code(sample.code)}</p>
            <p class="action mb-0">
              <.a id={"sample-#{sample.id}-check"} navigate={check_path(sample)}>Check it</.a>
            </p>
          </div>
        </div>
      </div>

      <p class="action mt-6">
        <.a id="samples-start" navigate={~p"/"}>Verify a card</.a>
      </p>
    </div>
    """
  end
end
