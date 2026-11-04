defmodule Web.DemoLive do
  use Web, :live_view_narrow_layout

  alias App.Model.DemoTeam
  alias App.Operation.CreateDemo
  alias App.ViewModel.DemoStartViewModel

  # Try a demo (#857): one button, and a name if they like. It makes the demo and opens
  # its link (Web.DemoController), which logs in and builds the copy. No email: an agent
  # can start one for the person it's helping, and the link is how they share it.

  def mount(_params, session, socket) do
    user = socket.assigns[:current_user]

    {:ok,
     socket
     |> assign(
       page_title: "Try SAR Duty",
       page_description: "Try SAR Duty on a made-up search and rescue team of your own.",
       client_ip: session["client_ip"],
       own_demo?: user != nil and DemoTeam.for_user(user) != nil
     )
     |> assign_form(DemoStartViewModel.build_new_changeset())}
  end

  def render(assigns) do
    ~H"""
    <h1 class="heading">Try SAR Duty</h1>
    <p class="lead">Try it on Coast Range SAR, a made-up team of your own.</p>
    <p :if={@own_demo?} id="demo-own">
      You have a demo open. <.a href={~p"/demo/building"}>Go to your demo</.a>
    </p>
    <.form for={@form} id="demo-form" phx-submit="start" phx-change="validate">
      <.input field={@form[:name]} label="Your name (optional)" autocomplete="name">
        You join the team as a team admin, beside Alex Chen.
      </.input>
      <ul id="demo-expect" class="hint">
        <li>It is yours alone, and its link opens it on any device.</li>
        <li>It sends nothing. Its emails wait in its Outbox for you to read.</li>
        <li>It is deleted after {days()}, or sooner if you choose.</li>
      </ul>
      <.form_actions>
        <.button id="demo-start" variant={:success} phx-disable-with="Starting…">
          Start a demo
        </.button>
      </.form_actions>
      <p class="hint">
        Agents can start one too: <.a navigate={~p"/agents"}>Agents</.a>.
        <.a navigate={~p"/privacy"}>Privacy</.a>
        says what SAR Duty keeps.
      </p>
    </.form>
    """
  end

  def handle_event("validate", %{"demo_start_view_model" => params}, socket) do
    changeset =
      params |> DemoStartViewModel.build_new_changeset() |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("start", %{"demo_start_view_model" => params}, socket) do
    case CreateDemo.call(params, kind: :visitor, ip: socket.assigns.client_ip) do
      {:ok, demo} ->
        {:noreply, redirect(socket, to: ~p"/demo/open/#{DemoTeam.link_token(demo)}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, CreateDemo.error_text(reason))}
    end
  end

  defp days, do: Service.Format.count(DemoTeam.days(), one: "%d day", many: "%d days")

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
end
