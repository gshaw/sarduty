defmodule Web.ErrorHTML do
  use Web, :html

  def render("404.html", assigns) do
    ~H"""
    <.render_custom_error
      code="404"
      description="Not found"
      help_text="SAR Duty cannot find this page. Check the address, or start from the home page."
    />
    """
  end

  def render("429.html", assigns) do
    ~H"""
    <.render_custom_error
      code="429"
      description="Too many requests"
      help_text="Wait a few minutes and try again. SAR Duty limits how often a connection can ask."
    />
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <.render_custom_error
      code="500"
      description="Internal server error"
      help_text="SAR Duty stopped working on this page, and we know about it. Reload the page to try again."
    />
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp render_custom_error(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="description" content="Helpful tools for search and rescue managers." />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title suffix=" · SAR Duty">
          {@code} {@description}
        </.live_title>
        <Web.Layouts.favicon_links />
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script phx-track-static type="module" src={~p"/assets/js/app.js"}>
        </script>
      </head>
      <body>
        <.site_bar size={:narrow} />

        <main role="main" class="max-w-md m-auto px-2 pt-8 mb-6">
          <h1 class="my-6">
            <div class="title-hero mb-0">{@code}</div>
            <div class="title text-danger-text">SAR Duty cannot show this page</div>
          </h1>
          <p class="heading">{@description}</p>
          <p class="mb-6">{@help_text}</p>
          <p>
            <a href="/" class="link">Home page</a>
          </p>
        </main>
      </body>
    </html>
    """
  end
end
