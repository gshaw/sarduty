defmodule Web.DemoLive do
  use Web, :live_view_narrow_layout

  alias App.Operation.RequestDemo
  alias App.ViewModel.DemoRequestViewModel

  # Try a demo (#857): a name and an email, then the code the email has. Opening the
  # link, or entering the code, posts to Web.DemoController, which logs in and builds
  # the copy. The name joins Coast Range SAR as a team admin beside Alex Chen.

  def mount(params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Try SAR Duty",
       page_description: "Try SAR Duty on a made-up search and rescue team of your own.",
       client_ip: session["client_ip"],
       sent: nil,
       code_form: to_form(%{"code" => ""}, as: "demo"),
       code_error: params["error"] == "code"
     )
     |> assign_form(DemoRequestViewModel.build_new_changeset())}
  end

  def render(assigns) do
    ~H"""
    <div :if={@sent} id="demo-sent">
      <h1 class="heading">Check your email</h1>
      <p>
        We emailed <strong>{@sent.email}</strong> a link to open your demo. It works for 24 hours.
      </p>
      <.form for={@code_form} id="code-form" action={~p"/demo/open"} method="post">
        <input type="hidden" name="demo[id]" value={@sent.id} />
        <.input
          field={@code_form[:code]}
          label="Or enter the code from the email"
          inputmode="numeric"
          autocomplete="one-time-code"
          class="font-mono"
        />
        <.form_actions>
          <.button variant={:success}>Open your demo</.button>
        </.form_actions>
      </.form>
    </div>
    <div :if={!@sent}>
      <h1 class="heading">Try SAR Duty</h1>
      <p class="lead">Try it on Coast Range SAR, a made-up team of your own.</p>
      <p :if={@code_error} id="code-error" class="text-danger-text">
        That link or code did not work. It lasts 24 hours. Ask for a new one below.
      </p>
      <.form for={@form} id="demo-form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} label="Your name" autocomplete="name">
          You join the team as a team admin, beside Alex Chen.
        </.input>
        <.input field={@form[:email]} type="email" label="Email" autocomplete="email">
          We email you a link to open it. You log in with this email.
        </.input>
        <ul id="demo-expect" class="hint">
          <li>It is yours alone. Nobody else sees it.</li>
          <li>Its emails come to you, and it never sends a text.</li>
          <li>It is deleted after 7 days, or sooner if you choose.</li>
        </ul>
        <.form_actions>
          <.button variant={:success} phx-disable-with="Sending…">Email me a link</.button>
        </.form_actions>
        <p class="hint">
          One demo per email. Asking again sends a new link to the same demo.
          <.a navigate={~p"/privacy"}>Privacy</.a>
          says what SAR Duty keeps.
        </p>
      </.form>
    </div>
    """
  end

  def handle_event("validate", %{"demo_request_view_model" => params}, socket) do
    changeset =
      params |> DemoRequestViewModel.build_new_changeset() |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"demo_request_view_model" => params}, socket) do
    case RequestDemo.call(params, socket.assigns.client_ip) do
      {:ok, demo} ->
        {:noreply, assign(socket, sent: demo)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, RequestDemo.error_text(reason))}
    end
  end

  # Swoosh's test adapter tells the process an email came from.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))
end
