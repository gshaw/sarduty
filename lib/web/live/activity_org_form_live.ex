defmodule Web.ActivityOrgFormLive do
  @moduledoc """
  An organization's form on an activity (#950), for team admins only: what SAR Duty
  filled in, what's missing with the page that fixes it, and the questions, with a row
  for each person a form asks about, such as On task, and their total, and each
  equipment use's total for a form that works one out. Answers save as
  they change (App.Operation.SaveFormAnswers), and each row's total follows them. Download draft PDF posts the form to
  Web.ActivityFormPDFController, which keeps the answers and sends a draft PDF, never saved.

  A form that's on publishes (#970, App.Operation.PublishDocument). One that says `signed
  by` is signed by whoever publishes it (#993): its task leader presses Sign and publish,
  and any other team admin Sign for Cameron Ruiz, which signs it in their own name for
  the task leader, after a confirm. When no one member has the task leader's name, the
  page says so, with the page that fixes it. Another team admin may instead ask the task
  leader to sign (App.Operation.AskToSign), the preview's main button when the task
  leader can log in; the page then says who it's waiting for, with Cancel request,
  until they sign. The Published box
  above the answers says when and who, with Download, the verify link, and Withdraw.
  When the form reads differently now, it says what changed and offers Publish again.
  Page 1 folds under it, and History lists every PDF published for the activity, as a
  tax credit letter's page does.

  The form is found on for the team's organization, and the activity through the team,
  so another organization's form, one turned off, or one not for this activity is a 404.
  """
  use Web, :live_view_app_layout

  import Web.Components.PublishedPDF

  alias App.Model.Activity
  alias App.Model.Form
  alias App.Model.FormAnswer
  alias App.Model.Member
  alias App.Model.PublishedPDF
  alias App.Model.SignRequest
  alias App.Operation.AskToSign
  alias App.Operation.PublishDocument
  alias App.Operation.ReadDocument
  alias App.Operation.SaveFormAnswers
  alias App.Operation.SignForm
  alias App.Operation.WithdrawDocument
  alias App.ViewData.ActivityForms
  alias App.ViewData.PublishedHistory
  alias Web.Components.ReportTable

  def mount(%{"id" => id, "form_id" => form_id}, _session, socket) do
    team = socket.assigns.current_team
    activity = team |> Activity.find!(id) |> App.Repo.preload(:team)
    if activity.deleted_at, do: raise(Web.Status.NotFound)
    form = Form.get_shown(team, form_id) || raise(Web.Status.NotFound)

    socket =
      assign(socket,
        page_title: "#{form.name} for #{activity.title}",
        activity: activity,
        form: form,
        errors: %{},
        preview: nil,
        ask: :none
      )

    case ActivityForms.load(team, activity, form, DateTime.utc_now()) do
      {:ok, page} ->
        socket = assign(socket, page: page, problem: nil, answers: page.answers, rows: page.rows)
        {:ok, assign_published(socket)}

      {:error, :not_shown} ->
        raise Web.Status.NotFound

      {:error, reason} ->
        {:ok,
         socket
         |> assign(page: nil, problem: reason, answers: %{}, rows: [])
         |> assign_published()}
    end
  end

  # The form's PDFs for the activity, and what changed since the current one.
  defp assign_published(socket) do
    %{current_team: team, activity: activity, form: form, page: page} = socket.assigns
    published = ActivityForms.published(team, activity, form)

    changes = changes(published.current, page, activity)

    # Who published and withdrew each, by their member names, as other "by" lines say.
    now = DateTime.utc_now()
    names = PublishedHistory.names(published.all, &Member.name_for_user(team, &1, now))

    socket
    |> assign_leader(now)
    |> assign(
      published: published,
      changes: changes,
      needed: if(page, do: ActivityForms.needed(page, socket.assigns.answers), else: []),
      attached: attached(page, socket.assigns.answers),
      published_by: published.current && names[published.current.user_id],
      history: PublishedHistory.rows(published.all, names)
    )
  end

  defp changes(nil, _page, _activity), do: []
  defp changes(_current, nil, _activity), do: []

  defp changes(current, page, activity),
    do: ActivityForms.changes(page, FormAnswer.starting(activity, page.doc.asks), current)

  # The task leader a signed form names with the answers, when it's on (#993), what the
  # page says when no one member has that name, and the open request to sign, which ends
  # once the name no longer names who it asks.
  defp assign_leader(socket, now) do
    %{current_team: team, form: form, page: page, answers: answers} = socket.assigns
    leader = if page && form.state == :on, do: ActivityForms.leader(page, answers, team, now)
    request = leader && socket |> open_request() |> AskToSign.check_leader(leader, now)

    assign(socket,
      leader: leader,
      leader_problem: leader && SignForm.problem(leader),
      request: request,
      asked_by: request && Member.name_for_user(team, request.asked_by, now)
    )
  end

  defp open_request(%{assigns: %{activity: activity, form: form}}),
    do: SignRequest.open_for(activity, form)

  # Each place whose text looks too long for its lines, so it goes on an attached page.
  defp attached(nil, _answers), do: []
  defp attached(page, answers), do: ActivityForms.attached(page, answers)

  # Publish opens its preview, /publish: the PDF printed once with the ID it publishes
  # under, every page as a picture, and what publishing does. Publish there keeps that
  # PDF. Printing takes a moment, so it runs once connected, not in the first render.
  def handle_params(_params, _uri, %{assigns: %{live_action: :publish}} = socket) do
    %{form: form, page: page, errors: errors} = socket.assigns

    cond do
      page == nil or form.state != :on ->
        {:noreply, back(socket, :error, "This form can't publish now.")}

      errors != %{} ->
        {:noreply, back(socket, :error, fix_first())}

      connected?(socket) ->
        {:noreply, start_preview(socket)}

      true ->
        {:noreply, assign(socket, preview: :printing)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, assign(socket, preview: nil)}

  defp start_preview(socket) do
    %{current_team: team, form: form, activity: activity, current_user: user} = socket.assigns
    current = socket.assigns.published.current

    socket
    |> assign(preview: :printing, preview_current_id: current && current.id, ask: :none)
    |> start_async(:preview, fn ->
      with {:ok, preview} <-
             PublishDocument.preview(team, form, activity, user, DateTime.utc_now()),
           {:ok, pages} <- Service.PDFImages.pages(preview.printed.attachment.content) do
        {:ok, Map.put(preview, :pages, pages)}
      end
    end)
  end

  # Whether the preview's task leader can be asked to sign, or why not.
  def handle_async(:preview, {:ok, {:ok, preview}}, socket) do
    ask =
      AskToSign.askable(preview.printed.signed, socket.assigns.current_team, DateTime.utc_now())

    {:noreply, assign(socket, preview: preview, ask: ask)}
  end

  def handle_async(:preview, {:ok, {:error, message}}, socket),
    do: {:noreply, back(socket, :error, message)}

  def handle_async(:preview, {:exit, _reason}, socket),
    do: {:noreply, back(socket, :error, "The preview did not print. Try again.")}

  defp back(socket, kind, message) do
    %{current_team: team, activity: activity, form: form} = socket.assigns

    socket
    |> put_flash(kind, message)
    |> push_patch(to: ~p"/teams/#{team}/activities/#{activity.id}/forms/#{form.id}")
  end

  # Each change saves the answers that read, and shows what's wrong with the rest. What
  # was typed stays in the boxes either way, and each row's total follows what reads.
  def handle_event("change", %{"answers" => typed}, %{assigns: %{page: %{}}} = socket) do
    %{activity: activity, page: page, current_user: user} = socket.assigns

    errors =
      case SaveFormAnswers.call(activity, page.doc, typed, user) do
        {:ok, _answers} -> %{}
        {:error, errors} -> errors
      end

    answers = Map.merge(socket.assigns.answers, typed)
    rows = ActivityForms.rows(page.doc, page.values, answers, page.timezone)

    {:noreply,
     socket |> assign(answers: answers, rows: rows, errors: errors) |> assign_published()}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  # A box that shows an error isn't saved, so publishing then would print its last saved
  # answer, not what the box shows.
  def handle_event("preview", _params, %{assigns: %{errors: errors}} = socket)
      when errors != %{} do
    {:noreply, put_flash(socket, :error, fix_first())}
  end

  # What publishing needs stays a message, so the button never greys out (#995).
  def handle_event("preview", _params, %{assigns: %{needed: [_ | _] = needed}} = socket),
    do: {:noreply, put_flash(socket, :error, ReadDocument.needed_error("This form", needed))}

  def handle_event("preview", _params, socket) do
    %{current_team: team, activity: activity, form: form} = socket.assigns

    {:noreply,
     push_patch(socket, to: ~p"/teams/#{team}/activities/#{activity.id}/forms/#{form.id}/publish")}
  end

  def handle_event("publish", _params, %{assigns: %{preview: %{code: _code} = preview}} = socket) do
    %{current_team: team, form: form, activity: activity, current_user: user} = socket.assigns
    current_id = socket.assigns.preview_current_id

    case PublishDocument.publish(team, form, activity, user, preview, current_id) do
      {:ok, pdf} ->
        {:noreply,
         socket |> assign_published() |> back(:info, "Published #{form.name}, #{code(pdf)}.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("publish", _params, socket), do: {:noreply, socket}

  def handle_event("ask", _params, %{assigns: %{preview: %{code: _code} = preview}} = socket) do
    %{current_team: team, form: form, activity: activity, current_user: user} = socket.assigns

    case AskToSign.call(team, form, activity, user, preview) do
      {:ok, _request} ->
        name = preview.printed.signed.leader.name
        {:noreply, socket |> assign_published() |> back(:info, "Asked #{name} to sign.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("ask", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-request", _params, %{assigns: %{request: %{} = request}} = socket) do
    %{current_team: team, current_user: user} = socket.assigns

    case AskToSign.cancel(team, request, user) do
      {:ok, _ended} ->
        {:noreply,
         socket
         |> assign_published()
         |> put_flash(:info, "Cancelled the request to #{request.member.name}.")}

      {:error, message} ->
        {:noreply, socket |> assign_published() |> put_flash(:error, message)}
    end
  end

  def handle_event("cancel-request", _params, socket), do: {:noreply, assign_published(socket)}

  def handle_event("withdraw", _params, socket) do
    %{current_team: team, current_user: user, published: %{current: pdf}} = socket.assigns

    case pdf && WithdrawDocument.call(team, pdf, user, DateTime.utc_now()) do
      {:ok, pdf} ->
        {:noreply, socket |> assign_published() |> put_flash(:info, "Withdrew #{code(pdf)}.")}

      {:error, message} ->
        {:noreply, socket |> assign_published() |> put_flash(:error, message)}

      nil ->
        {:noreply, assign_published(socket)}
    end
  end

  defp code(pdf), do: PublishedPDF.format_code(pdf.code)

  defp fix_first, do: "Fix the boxes marked first. Publish prints what's saved."

  def render(%{live_action: :publish} = assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={@activity.ref_id || @activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item
        label={@form.name}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}/forms/#{@form.id}"}
      />
      <:item label="Publish" />
    </.breadcrumbs>
    <h1 class="title">Publish {@form.name}</h1>
    <p class="lead measure">
      Check every page. Publish keeps this PDF, exactly as it shows here.
    </p>

    <div class="content-wrapper">
      <aside class="content-1/3">
        <h2 class="heading">What Publish does</h2>
        <p :if={@preview == :printing} class="hint">Printing the preview…</p>
        <dl :if={is_map(@preview)} id="publish-what">
          <dt>ID</dt>
          <dd id="publish-id">
            <span class="mono">{PublishedPDF.format_code(@preview.code)}</span>
            <span class="hint block">SAR Duty keeps the PDF for your team's admins.</span>
          </dd>
          <dt>Verify page</dt>
          <dd id="publish-verify">
            {Web.VerifyHost.host()}
            <span :if={@preview.printed.shows == []} class="hint block">
              Shows your team and the date it was published.
            </span>
            <div :if={@preview.printed.shows != []} class="value-rows text-sm mt-1">
              <div :for={shown <- @preview.printed.shows}>
                <span>{shown["label"]}</span>
                <strong>{shown["text"] || "blank"}</strong>
              </div>
            </div>
          </dd>
          <dt>Signature</dt>
          <dd id="publish-signature">
            <.signature signed={@preview.printed.signed} ask={@ask} />
          </dd>
          <%= if @published.current do %>
            <dt>Replaces</dt>
            <dd id="publish-replaces">
              <span class="mono">{PublishedPDF.format_code(@published.current.code)}</span>
              <span class="hint block">Its verify page then says Replaced.</span>
            </dd>
          <% end %>
          <dt>Sent to</dt>
          <dd id="publish-not-sent">
            <%= if SignForm.tells_leader?(@preview.printed.signed) do %>
              {@preview.printed.signed.leader.name}, the task leader
            <% else %>
              No one
            <% end %>
            <span class="hint block">Download it once it's published, and send it yourself.</span>
          </dd>
        </dl>
        <.form_actions>
          <.button
            :if={@ask == :ok}
            id="publish-ask"
            type="button"
            variant={:primary}
            phx-click="ask"
            phx-disable-with="Asking…"
          >
            Ask {@preview.printed.signed.leader.name} to sign
          </.button>
          <.button
            id="publish-confirm"
            type="button"
            variant={if @ask == :ok, do: :secondary, else: :primary}
            phx-click="publish"
            phx-disable-with="Publishing…"
            disabled={!is_map(@preview)}
            {sign_confirm(@preview)}
          >
            {publish_label(@preview)}
          </.button>
          <.button
            id="publish-back"
            patch={~p"/teams/#{@current_team}/activities/#{@activity.id}/forms/#{@form.id}"}
          >
            Back to answers
          </.button>
        </.form_actions>
      </aside>
      <main class="content-2/3">
        <div :if={is_map(@preview)} id="publish-pages" class="flex flex-col gap-4">
          <img
            :for={{png, n} <- Enum.with_index(@preview.pages, 1)}
            id={"publish-page-#{n}"}
            src={"data:image/png;base64," <> Base.encode64(png)}
            alt={"Page #{n} of #{length(@preview.pages)} of the #{@form.name} as it publishes"}
            class="w-full border border-border-subtle shadow-sm"
          />
        </div>
      </main>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Activities" path={~p"/teams/#{@current_team}/activities"} />
      <:item
        label={@activity.ref_id || @activity.title}
        path={~p"/teams/#{@current_team}/activities/#{@activity.id}"}
      />
      <:item label={@form.name} />
    </.breadcrumbs>
    <.banner
      :if={@form.state == :testing}
      id="org-form-in-development"
      kind={:warning}
      title="Testing only"
      class="mb-6"
    >
      <p>This form is testing and not ready for real use. Don't send what it prints.</p>
    </.banner>
    <h1 class="title">{@page_title}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>

    <.banner :if={@problem} id="org-form-problem" kind={:danger} title="This form cannot print">
      <p>{@problem}</p>
      <p>Ask for help with Get help.</p>
    </.banner>

    <.out_of_date
      :if={@page}
      id="org-form-out-of-date"
      noun="form"
      changes={@changes}
      next={@form.state == :on && "Publish again makes a new one."}
    />
    <.needed_banner
      :if={@page && @form.state == :on}
      id="org-form-needed"
      what="This form"
      needed={@needed}
      team={@current_team}
      activity={@activity}
    />

    <.banner
      :if={@leader_problem}
      id="org-form-leader"
      kind={:warning}
      title={@leader_problem}
      class="mb-6 measure"
    >
      <p>
        A team admin who signs it signs for {@leader.name}, and nobody gets an email.
        <%= if fix = @leader.field && fix(@leader.field, @current_team, @activity) do %>
          Check the {@leader.field.label} with <.a id="org-form-leader-fix" navigate={fix.path}>{fix.in_text}</.a>.
        <% end %>
      </p>
    </.banner>

    <.banner
      :for={place <- @attached}
      id={"org-form-attached-#{place.name}"}
      title={"#{place.more} goes on an attached page"}
      class="mb-6"
    >
      <p>
        It's too long for its {Service.Format.count(place.lines, one: "%d line", many: "%d lines")}, so they say See attached page. The PDF ends with the whole text on a page of its own.
      </p>
    </.banner>

    <div :if={@page} class="measure">
      <.waiting :if={@request} request={@request} asked_by={@asked_by} team={@current_team} />
      <.published_box
        published={@published}
        published_by={@published_by}
        errors={@errors}
        form={@form}
        team={@current_team}
      />
      <.history id="org-form-history" rows={@history} team={@current_team} />

      <section :if={@page.missing != []} id="org-form-missing" class="mb-8">
        <h2 class="heading">Missing</h2>
        <p class="mb-4">
          {Service.Format.count(length(@page.missing),
            one: "%d value this form reads is empty. Fill it in, and every form gets it.",
            many: "%d values this form reads are empty. Fill them in, and every form gets them."
          )} The PDF still prints with blanks.
        </p>
        <.read_table id="org-form-missing-table" rows={@page.missing} team={@current_team}>
          <:value :let={row}>
            <.badge kind={:warning}>Missing</.badge>
            <.a
              :if={fix = fix(row, @current_team, @activity)}
              id={"org-form-fix-#{row_id(row)}"}
              class="ml-2"
              navigate={fix.path}
            >{fix.label}</.a>
          </:value>
        </.read_table>
      </section>

      <section :if={@page.filled != []} id="org-form-filled" class="mb-8">
        <h2 class="heading">Filled in by SAR Duty</h2>
        <.read_table id="org-form-filled-table" rows={@page.filled} team={@current_team}>
          <:value :let={row}>{ReportTable.value_text(row.value, row.column, @current_team)}</:value>
        </.read_table>
      </section>

      <.form
        for={%{}}
        as={:answers}
        id="org-form-answers"
        action={~p"/teams/#{@current_team}/activities/#{@activity.id}/forms/#{@form.id}/pdf"}
        method="post"
        phx-change="change"
      >
        <%!-- Enter in a box would download a PDF: a disabled first button stops it. --%>
        <button type="submit" disabled hidden aria-hidden="true"></button>
        <section :if={ActivityForms.questions(@page.doc) != []} id="org-form-questions" class="mb-8">
          <h2 class="heading">Questions</h2>
          <p class="hint mb-4">
            Your answers stay with this activity. Another form that asks the same thing starts from them.
          </p>
          <.ask
            :for={ask <- ActivityForms.questions(@page.doc)}
            ask={ask}
            type={App.Document.ask_type(@page.doc, ask)}
            value={@answers[ask.name]}
            errors={List.wrap(@errors[ask.name])}
          />
        </section>
        <.rows_table
          :for={table <- @rows}
          table={table}
          doc={@page.doc}
          team={@current_team}
          errors={@errors}
        />
        <p :if={@form.state == :on} class="hint">
          A draft says DRAFT on every page and is never kept. Publish keeps the PDF, with an ID
          anyone holding it can check.
        </p>
        <p
          :if={@form.state == :on and @errors != %{}}
          id="org-form-fix-first"
          class="text-danger-text"
        >
          {fix_first()}
        </p>
        <.form_actions>
          <.button
            :if={@form.state == :on and is_nil(@published.current)}
            id="org-form-publish"
            type="button"
            variant={:primary}
            phx-click="preview"
            disabled={@errors != %{}}
          >
            Publish
          </.button>
          <.button
            id="org-form-download"
            type="submit"
            variant={if @form.state == :on, do: :secondary, else: :primary}
          >
            Download draft PDF
          </.button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  attr :request, :map, required: true
  attr :asked_by, :string, default: nil
  attr :team, :map, required: true

  # The open request to sign (#993): who it waits for, and Cancel request.
  defp waiting(assigns) do
    ~H"""
    <section id="org-form-waiting" class="mb-8">
      <.heading_row>
        <h2 class="heading">Waiting for {@request.member.name} to sign</h2>
        <:action>
          <.button
            id="org-form-cancel-request"
            type="button"
            size={:sm}
            phx-click="cancel-request"
            phx-disable-with="Cancelling…"
          >
            Cancel request
          </.button>
        </:action>
      </.heading_row>
      <p class="hint">
        Asked {Service.Format.date_short(@request.asked_at, @team.timezone)}{if @asked_by,
          do: " by #{@asked_by}"}. They get it in For you to do and by email.
      </p>
    </section>
    """
  end

  attr :signed, :map, default: nil, doc: "the preview's App.Operation.SignForm signing, or nil"
  attr :ask, :any, default: :none, doc: "App.Operation.AskToSign.askable/3's"

  # Who signs the PDF as it publishes (#993): the task leader in their name, or this team
  # admin in theirs, for the task leader, or the task leader once asked.
  defp signature(%{signed: nil} = assigns), do: ~H"Left blank, to sign by hand"

  defp signature(%{signed: %{signed_for: nil}} = assigns) do
    ~H"""
    /s/ {@signed.signed_by}
    <span class="hint block">You're the task leader. It's dated today.</span>
    """
  end

  defp signature(%{signed: %{leader: nil}} = assigns) do
    ~H"""
    {@signed.problem}.
    <span class="hint block">You sign it in your name: {signed_words(@signed)}.</span>
    """
  end

  defp signature(assigns) do
    ~H"""
    {@signed.leader.name}, the task leader, signs this form.
    <span :if={@ask == :ok} class="hint block">
      Ask them, and they sign it from an email. Or sign it in your name: {signed_words(@signed)}.
    </span>
    <span :if={@ask != :ok} class="hint block">
      You can sign it in your name: {signed_words(@signed)}.
    </span>
    <span :if={match?({:error, _}, @ask)} id="publish-cant-ask" class="hint block">
      {elem(@ask, 1)}
    </span>
    """
  end

  defp signed_words(signed), do: "/s/ #{signed.signed_by} for #{signed.signed_for}"

  # Publish, or for a signed form who signs it.
  defp publish_label(%{printed: %{signed: %{signed_for: nil}}}), do: "Sign and publish"
  defp publish_label(%{printed: %{signed: %{signed_for: whom}}}), do: "Sign for #{whom}"
  defp publish_label(_preview), do: "Publish"

  # Signing for the task leader asks first (#993): it's in this admin's name, and says
  # whether the task leader hears.
  defp sign_confirm(%{printed: %{signed: %{signed_for: whom} = signed} = printed})
       when is_binary(whom) do
    %{
      "data-confirm" =>
        "Sign #{printed.attachment.title} yourself? It will read #{signed_words(signed)}. #{tells(signed)}",
      "data-confirm-button" => "Sign for #{whom}"
    }
  end

  defp sign_confirm(_preview), do: %{}

  defp tells(%{leader: nil} = signed),
    do: "#{signed.problem}, so nobody gets an email."

  defp tells(signed) do
    if SignForm.tells_leader?(signed),
      do: "#{signed.leader.name} gets an email with the PDF.",
      else: "#{signed.leader.name} has no email, so they won't hear about it."
  end

  attr :published, :map, required: true
  attr :published_by, :string, default: nil
  attr :errors, :map, required: true
  attr :form, :map, required: true
  attr :team, :map, required: true

  # The current PDF in the Published section a letter has (#995), with Publish again,
  # plain: its preview page is the confirm. Page 1 folds under it, since the answers
  # follow.
  defp published_box(assigns) do
    ~H"""
    <%= if pdf = @published.current do %>
      <.published_section prefix="org-form" pdf={pdf} published_by={@published_by} team={@team}>
        <:actions>
          <.button
            :if={@form.state == :on}
            id="org-form-publish-again"
            type="button"
            phx-click="preview"
            disabled={@errors != %{}}
          >
            Publish again
          </.button>
        </:actions>
        <:withdraw>
          <.button
            id="org-form-withdraw"
            type="button"
            variant={:danger}
            phx-click="withdraw"
            phx-disable-with="Withdrawing…"
            {withdraw_confirm(pdf, "Withdraw")}
          >
            Withdraw
          </.button>
        </:withdraw>
      </.published_section>
      <.page_one
        prefix="org-form"
        src={~p"/teams/#{@team}/pdfs/#{pdf.id}/preview.png"}
        alt={"Page 1 of #{PublishedPDF.format_code(pdf.code)}"}
      />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :team, :map, required: true
  slot :value, required: true

  # Each value the form reads beside its field's name, as an activity's Fields tab shows
  # them.
  defp read_table(assigns) do
    ~H"""
    <div class="table-wrap">
      <table id={@id} class="table table-striped table-fields">
        <tbody>
          <tr :for={row <- @rows} id={"#{@id}-#{row_id(row)}"}>
            <th scope="row">{row.label}</th>
            <td>{render_slot(@value, row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :table, :map, required: true, doc: "one of ActivityForms.rows/4's"
  attr :doc, :map, required: true
  attr :team, :map, required: true
  attr :errors, :map, required: true

  # A row for each person or item the form asks about or works a total out for, with a
  # box for each answer and the row's total. A blank box takes the answer shown in grey.
  defp rows_table(assigns) do
    ~H"""
    <section id={"org-form-rows-#{@table.report}"} class="mb-8">
      <h2 class="heading">{String.capitalize(@table.report)}</h2>
      <p :for={hint <- blank_hints(@table.asks, @doc.asks)} class="hint mb-4">{hint}</p>
      <.table
        id={"org-form-rows-#{@table.report}-table"}
        rows={@table.rows}
        row_id={&"org-form-row-#{&1.dom}"}
        class="table-striped"
      >
        <:col :let={row} :if={@table.kind == :member} label="Member">
          <.member_cell member={%{id: row.id, name: row.name}} team={@team} />
        </:col>
        <:col :let={row} :if={@table.kind == :item} label="Item">
          <.item_cell item={%{title: row.name}} link={false} status={false} />
        </:col>
        <:col :let={row} :for={ask <- @table.asks} label={ask.label} class="w-px whitespace-nowrap">
          <.row_answer
            ask={ask}
            row={row}
            type={App.Document.ask_type(@doc, ask)}
            error={@errors |> Map.get(ask.name) |> row_error(row.key)}
          />
        </:col>
        <:col
          :let={row}
          :if={@table.total}
          label={@table.total}
          align="right"
          class="w-px whitespace-nowrap"
        >
          <span id={"org-form-total-#{row.dom}"}>{row.total}</span>
        </:col>
      </.table>
    </section>
    """
  end

  attr :ask, :map, required: true
  attr :row, :map, required: true
  attr :type, :atom, required: true
  attr :error, :string, default: nil

  defp row_answer(%{ask: %{choices: [_ | _]}} = assigns) do
    ~H"""
    <select
      id={"org-form-answer-#{@ask.name}-#{dom_key(@row.key)}"}
      name={"answers[#{@ask.name}][#{@row.key}]"}
      class={["w-auto", @error && "is-invalid"]}
      aria-label={"#{@ask.label} for #{@row.name}"}
    >
      {Phoenix.HTML.Form.options_for_select(
        @ask.choices,
        @row.answers[@ask.name] || @row.defaults[@ask.name]
      )}
    </select>
    <.error :if={@error}>{@error}</.error>
    """
  end

  defp row_answer(assigns) do
    ~H"""
    <input
      type={input_type(@type)}
      id={"org-form-answer-#{@ask.name}-#{dom_key(@row.key)}"}
      name={"answers[#{@ask.name}][#{@row.key}]"}
      value={@row.answers[@ask.name]}
      placeholder={@row.defaults[@ask.name]}
      step={@type == :number && "any"}
      min={@type == :number && "0"}
      class={[@type == :number && "w-16", @error && "is-invalid"]}
      aria-label={"#{@ask.label} for #{@row.name}"}
      phx-debounce="blur"
    />
    <.error :if={@error}>{@error}</.error>
    """
  end

  # A row's answer that starts from another answer: blank, it takes that one.
  defp blank_hints(asks, all) do
    for %{default: {:value, name, _line}} = ask <- asks,
        other = Enum.find(all, &(&1.name == name)),
        do: "Leave #{ask.label} blank to use #{other.label}."
  end

  defp row_error(errors, key) when is_map(errors), do: errors[key]
  defp row_error(_message, _key), do: nil

  defp dom_key(key), do: String.replace(key || "", ":", "-")

  attr :ask, :map, required: true
  attr :type, :atom, default: :text
  attr :value, :any, default: nil
  attr :errors, :list, default: []

  defp ask(%{ask: %{choices: [_ | _] = choices}} = assigns) do
    assigns = assign(assigns, options: Enum.map(choices, &{&1, &1}))

    ~H"""
    <.input
      id={"org-form-answer-#{@ask.name}"}
      name={"answers[#{@ask.name}]"}
      type="radios"
      label={@ask.label}
      options={@options}
      value={@value}
      errors={@errors}
    >
      {@ask.hint}
    </.input>
    """
  end

  defp ask(assigns) do
    ~H"""
    <.input
      id={"org-form-answer-#{@ask.name}"}
      name={"answers[#{@ask.name}]"}
      type={input_type(@type)}
      label={@ask.label}
      value={@value}
      errors={@errors}
      step={@type == :number && "any"}
      phx-debounce="blur"
    >
      {@ask.hint}
    </.input>
    """
  end

  defp input_type(:number), do: "number"
  defp input_type(:day), do: "date"
  defp input_type(_text), do: "text"

  defp row_id(row), do: row.name |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-")
end
