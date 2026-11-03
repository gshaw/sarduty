defmodule Web.DemoLive do
  use Web, :live_view_narrow_layout

  alias App.Model.DemoTeam
  alias App.Operation.RequestDemo
  alias App.Repo
  alias App.ViewModel.DemoRequestViewModel

  # Try a demo (#857): a name and an email, then the code the email has. The code step is
  # in the URL as a signed token, so a refresh keeps it. The code is checked here first,
  # so a blank or wrong one stays on this step; a right one posts to Web.DemoController,
  # which checks it again, logs in, and builds the copy. The emailed link goes there too.
  # The name joins Coast Range SAR as a team admin beside Alex Chen.

  @sent_salt "demo sent"

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Try SAR Duty",
       page_description: "Try SAR Duty on a made-up search and rescue team of your own.",
       client_ip: session["client_ip"],
       own_demo?: own_demo?(socket.assigns[:current_user])
     )
     |> assign_form(DemoRequestViewModel.build_new_changeset())}
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       sent: sent_demo(params["sent"]),
       link_error: params["error"] == "code",
       trigger_submit: false
     )
     |> assign_code_form(%{"code" => ""})}
  end

  defp own_demo?(nil), do: false
  defp own_demo?(user), do: DemoTeam.get_by_email(user.email) != nil

  defp sent_demo(nil), do: nil

  defp sent_demo(token) do
    case Phoenix.Token.verify(Web.Endpoint, @sent_salt, token, max_age: 86_400) do
      {:ok, id} -> Repo.get(DemoTeam, id)
      {:error, _reason} -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div :if={@sent} id="demo-sent">
      <h1 class="heading">Check your email</h1>
      <p>
        We emailed <strong>{@sent.email}</strong> a link to open your demo. It works for 24 hours.
      </p>
      <.form
        for={@code_form}
        id="code-form"
        action={~p"/demo/open"}
        method="post"
        phx-submit="open"
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name="demo[id]" value={@sent.id} />
        <.input
          field={@code_form[:code]}
          label="Or enter the code from the email"
          required
          inputmode="numeric"
          autocomplete="one-time-code"
          maxlength="7"
          class="font-mono"
        />
        <.form_actions>
          <.button
            id="code-submit"
            variant={:success}
            disabled={@trigger_submit}
            phx-disable-with="Opening…"
          >
            {if @trigger_submit, do: "Opening…", else: "Open your demo"}
          </.button>
        </.form_actions>
      </.form>
      <p class="text-text-muted">
        No email after a few minutes? Check your spam folder.
      </p>
      <p :if={Web.Layouts.dev_mailbox?()} id="demo-dev-mailbox">
        In development the email is in the <.a href="/dev/mailbox" external={true}>local mailbox</.a>.
      </p>
      <p class="action">
        <.a id="demo-resend" href="#" phx-click="resend" phx-disable-with="Sending…">Email me a new code</.a>
      </p>
      <p class="action">
        <.a id="demo-again" patch={~p"/demo"}>Use a different email</.a>
      </p>
    </div>
    <div :if={!@sent}>
      <h1 class="heading">Try SAR Duty</h1>
      <p class="lead">Try it on Coast Range SAR, a made-up team of your own.</p>
      <p :if={@own_demo?} id="demo-own">
        You have a demo already. <.a href={~p"/demo/building"}>Open your demo</.a>
      </p>
      <p :if={@link_error} id="code-error" class="text-danger-text">
        That link did not work. It lasts 24 hours. Ask for a new one below.
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
        {:noreply, push_patch(socket, to: sent_path(demo))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, RequestDemo.error_text(reason))}
    end
  end

  # A blank or wrong code stays here. A right one posts the form to the controller.
  def handle_event("open", %{"demo" => %{"code" => code} = params}, socket) do
    demo = Repo.reload(socket.assigns.sent)

    case demo && DemoTeam.check_code(demo, code, DateTime.utc_now(:second)) do
      :ok ->
        {:noreply, socket |> assign_code_form(params) |> assign(trigger_submit: true)}

      :blank ->
        {:noreply, assign_code_form(socket, params, "Enter the 6-digit code from the email.")}

      :wrong ->
        {:noreply, assign_code_form(socket, params, "That code is not right. Check the email.")}

      _expired_or_gone ->
        {:noreply,
         assign_code_form(socket, params, "That code has expired. Email yourself a new one.")}
    end
  end

  def handle_event("resend", _params, socket) do
    %DemoTeam{name: name, email: email} = socket.assigns.sent

    case RequestDemo.call(%{"name" => name, "email" => email}, socket.assigns.client_ip) do
      {:ok, demo} ->
        {:noreply,
         socket
         |> put_flash(:info, "We emailed a new code to #{email}.")
         |> push_patch(to: sent_path(demo))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, push_patch(socket, to: ~p"/demo")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, RequestDemo.error_text(reason))}
    end
  end

  # Swoosh's test adapter tells the process an email came from.
  def handle_info({:email, _email}, socket), do: {:noreply, socket}

  defp sent_path(demo),
    do: ~p"/demo?#{[sent: Phoenix.Token.sign(Web.Endpoint, @sent_salt, demo.id)]}"

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  defp assign_code_form(socket, params, error \\ nil) do
    errors = if error, do: [code: {error, []}], else: []
    assign(socket, :code_form, to_form(params, as: "demo", errors: errors))
  end
end
