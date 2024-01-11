defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  alias App.Mailer.TaxCreditLetterMailer
  alias App.Model.TaxCreditLetter
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    letter = TaxCreditLetter.find!(socket.assigns.current_team, params["id"])

    socket =
      socket
      |> assign(:page_title, "#{letter.member.name}ʼs #{letter.year} Tax Credit Letter")
      |> assign(:letter, letter)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs team={@current_team}>
      <:item
        label={"#{@letter.year} Tax Credit Letters"}
        path={~p"/#{@current_team.subdomain}/tax-credit-letters?year=#{@letter.year}"}
      />
      <:item label={@letter.ref_id} />
    </.breadcrumbs>

    <h1 class="title"><%= @page_title %></h1>
    <.form_actions>
      <a
        href={~p"/#{@current_team.subdomain}/tax-credit-letters/#{@letter.id}/pdf"}
        class="btn btn-success"
      >
        Download PDF
      </a>
      <button phx-click="email" class="btn btn-warning">Email PDF to member</button>
      <:trailing>
        <button phx-click="destroy" class="btn btn-danger">Delete</button>
      </:trailing>
    </.form_actions>
    <hr class="my-p" />

    <div class="content-wrapper">
      <aside class="content-1/3">
        <dl>
          <dt>Member</dt>
          <dd>
            <%= @letter.member.name %><br /><%= @letter.member.email %>
          </dd>
          <dt>Created</dt>
          <dd><%= Service.Format.short_datetime(@letter.inserted_at, @current_team.timezone) %></dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <.markdown content={@letter.letter_content} />
      </main>
    </div>
    """
  end

  def handle_event("email", _unsigned_params, socket) do
    tax_credit_letter = socket.assigns.letter

    Task.start(fn -> TaxCreditLetterMailer.deliver_tax_credit_letter(tax_credit_letter) end)

    socket =
      socket
      |> put_flash(:info, "Email sent to #{tax_credit_letter.member.email}")

    {:noreply, socket}
  end

  def handle_event("destroy", _unsigned_params, socket) do
    tax_credit_letter = socket.assigns.letter
    Repo.delete!(tax_credit_letter)

    socket =
      socket
      |> put_flash(:info, "Tax credit letter deleted")
      |> redirect(
        to:
          ~p"/#{socket.assigns.current_team.subdomain}/tax-credit-letters?year=#{tax_credit_letter.year}"
      )

    {:noreply, socket}
  end
end
