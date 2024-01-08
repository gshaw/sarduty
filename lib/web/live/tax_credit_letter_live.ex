defmodule Web.TaxCreditLetterLive do
  use Web, :live_view_app_layout

  import Ecto.Query

  alias App.Model.TaxCreditLetter
  alias App.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    letter = find_tax_credit_letter(params["id"], socket.assigns.current_team)

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
      <%!-- <button disabled class="btn btn-warning">Email PDF to member</button> --%>
      <span class="badge badge-warning">Email PDF to member under construction</span>
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

  defp find_tax_credit_letter(tax_credit_letter_id, current_team) do
    query =
      from(tcl in TaxCreditLetter,
        left_join: m in assoc(tcl, :member),
        where: tcl.id == ^tax_credit_letter_id,
        where: m.team_id == ^current_team.id,
        preload: [:member]
      )

    Repo.one(query)
  end
end
