defmodule App.Mailer.DemoMailer do
  @moduledoc """
  Try a demo's own emails (#857), from SAR Duty to the visitor: the link that opens the
  demo, and the day before it goes. The link email holds no name: anyone can type any
  address on the form, so it must say nothing they chose.
  """
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.DemoTeam

  @button "display:inline-block;padding:10px 16px;border-radius:4px;font-weight:700;text-decoration:none;background:#00703c;color:#ffffff;"

  @doc "The link that opens the demo, with its code for a phone that opens links elsewhere."
  def deliver_link(%DemoTeam{} = demo, code) do
    url = open_url(demo, code)
    host = Web.Endpoint.host()

    new()
    |> to(demo.email)
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> subject("Your SAR Duty demo code: #{code}")
    |> text_body("""
    Open your demo of SAR Duty, on a made-up team of your own:

    #{url}

    Or enter this code on the demo page:

    #{code}

    It works for 24 hours. If you did not ask for a demo, ignore this email and nothing is made.

    @#{host} ##{code}
    """)
    |> html_body("""
    <div style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:16px;max-width:480px">
      <p>Open your demo of SAR Duty, on a made-up team of your own.</p>
      <p><a href="#{Plug.HTML.html_escape(url)}" style="#{@button}">Open your demo</a></p>
      <p>Or enter this code on the demo page:</p>
      <p style="margin:24px 0;font-size:32px;font-weight:700;letter-spacing:6px;font-family:ui-monospace,Menlo,monospace">#{code}</p>
      <p style="font-size:14px">It works for 24 hours. If you did not ask for a demo, ignore this email and nothing is made.</p>
      <p style="display:none;font-size:0;line-height:0;max-height:0;overflow:hidden">@#{host} ##{code}</p>
    </div>
    """)
    |> Mailer.deliver()
  end

  @doc "The demo goes tomorrow, and how to keep using SAR Duty."
  def deliver_ending(%DemoTeam{} = demo) do
    new()
    |> to({demo.name, demo.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> reply_to(App.Support.email())
    |> subject("Your SAR Duty demo goes tomorrow")
    |> text_body("""
    Your demo of SAR Duty, on Coast Range SAR, is deleted tomorrow, with your name and email.

    To keep using SAR Duty, sign up your own team:
    #{Web.Endpoint.url()}/signup

    Reply to this email with any questions.
    """)
    |> Mailer.deliver()
  end

  @doc "Where the link goes: it logs in, then builds the demo the first time."
  def open_url(%DemoTeam{id: id}, code), do: "#{Web.Endpoint.url()}/demo/open/#{id}?code=#{code}"
end
