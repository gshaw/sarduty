defmodule Web.ErrorHTML do
  use Web, :html

  def render("404.html", assigns) do
    ~H"""
    <.render_custom_error
      code="404"
      description="Not found"
      help_text="The requested page was not found on this server."
    />
    """
  end

  def render("429.html", assigns) do
    ~H"""
    <.render_custom_error
      code="429"
      description="Too many requests"
      help_text="The server is limiting requests for a period of time. Wait a few minutes and try again."
    />
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <.render_custom_error
      code="500"
      description="Internal server error"
      help_text="We've been notified. Try refreshing the page as the problem may be temporary."
    />
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp render_custom_error(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="[scrollbar-gutter:stable]" data-theme="tailwind">
      <head>
        <meta charset="utf-8" />
        <meta name="description" content="Helpful tools for search and rescue managers." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · SAR Duty">
          {assigns[:page_title] || "Untitled Page"}
        </.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
        </script>
      </head>
      <body class="bg-base-1 text-base-content">
        <.navbar size={:narrow} color={:base_2}>
          <.navbar_links>
            <.a kind={:navbar_title} navigate="/">SAR Duty</.a>
          </.navbar_links>
        </.navbar>

        <main role="main" class="max-w-narrow m-auto px-2 pt-16 mb-p2">
          <div class="mx-auto max-w-2xl">
            <h1 class="my-p2">
              <div class="title-hero mb-0">{@code}</div>
              <div class="title text-danger-1">That&rsquo;s an error</div>
            </h1>
            <p class="heading">{@description}</p>
            <p class="mb-p2">{@help_text}</p>
            <p>
              <a href="/" class="link">
                Home Page
              </a>
            </p>
          </div>
        </main>
      </body>
    </html>
    """
  end
end
