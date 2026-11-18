defmodule Web.FormLive do
  use Web, :live_view_app_layout

  import Web.Components.AIWriting, only: [draft_waiting: 1]
  import Web.Components.FormSample

  alias App.Document
  alias App.Model.AIDraft
  alias App.Model.CustomField
  alias App.Model.Form
  alias App.Model.Organization
  alias App.Operation.AskAI
  alias App.Operation.CopyForm
  alias App.Operation.DeleteForm
  alias App.Operation.SaveDraft
  alias App.Operation.SaveForm
  alias App.Operation.SetFormState
  alias App.Operation.TryForm
  alias App.Repo
  alias Web.Components.FormSample
  alias Web.FormOwner

  # One form (#950), an organization's or a team's own (#1083), found through its owner,
  # so another's is a 404. The page shows the form: its Sample, tried on an activity it
  # shows on and drawn as pictures as Change form draws it (Web.Components.FormSample),
  # on Coast Range SAR, a made-up team, for an organization's, and on the team's own
  # activities for a team's, with Download sample PDF. Before it's written (#1088), the
  # agency's blank page. Its text folds under Show how it fills in. The sidebar: Ready to
  # try and Ready to publish, two switches for three states (#970) that save as they're
  # flipped, then Shows on, Version, Actions, and Questions last, since they run long,
  # each with its type and how it starts. With AI writing open, its admins write it on
  # Change form (#1089). Delete form shows while no PDF was published from it; after,
  # turning it off is the way.
  #
  # While its admin has a draft from Change form (#1089), a banner says so, to them alone,
  # with Open Change form and Discard them.
  #
  # On a team's page, its organization's form is read-only: its state as a fact where the
  # switches sit, the sample on the team's own activities, and its text. With team forms
  # on, its team admins copy it as their own to change (App.Operation.CopyForm).
  def mount(%{"id" => id}, _session, socket) do
    owner = FormOwner.viewer(socket.assigns)
    {form, own?} = FormOwner.form!(owner, id)

    socket
    |> assign(page_title: form.name, owner: owner, own?: own?)
    |> assign_actions(form, owner, own?, socket.assigns.current_user)
    |> assign_draft(form)
    |> assign(activity: nil, activities: [], pages: [], preview_error: nil)
    |> assign_form(form)
    |> preview()
    |> then(&{:ok, &1})
  end

  # What the user may do with it: the owner's own form, or on a team's page, its
  # organization's, read-only, which they may copy.
  defp assign_actions(socket, form, owner, true = _own?, user),
    do:
      assign(socket,
        change?: change?(owner, user),
        delete?: DeleteForm.allowed?(form, user),
        copy?: false,
        from: nil,
        replaced?: Form.replaced?(form, owner)
      )

  defp assign_actions(socket, _form, team, false = _own?, user),
    do:
      assign(socket,
        change?: false,
        delete?: false,
        copy?: CopyForm.allowed?(team, user),
        from: Repo.preload(team, :organization).organization,
        replaced?: false
      )

  # The person's own draft, while they may still change the form.
  defp assign_draft(%{assigns: %{change?: true, current_user: user}} = socket, form),
    do: assign(socket, draft: AIDraft.get(user, form))

  defp assign_draft(socket, _form), do: assign(socket, draft: nil)

  # Change form writes the form with AI writing (#1089), for whoever saves the owner's
  # forms while AI writing is open to them.
  defp change?(owner, user),
    do:
      SaveForm.allowed?(owner, user) and
        AskAI.check(owner, user, DateTime.utc_now(), :form) != {:error, :off}

  defp assign_form(socket, form) do
    page = Form.page_bytes(form)

    assign(socket,
      form: form,
      doc: form.text |> parse() |> checked(socket.assigns.owner),
      page: page,
      page_count: page && page_count(page)
    )
  end

  # Checked where it's tried, for each question's type; unchecked, the questions show
  # without one.
  defp checked(nil, _owner), do: nil

  defp checked(doc, owner) do
    with {%{} = context, _repo} <- TryForm.context(owner, DateTime.utc_now()),
         {:ok, checked} <- Document.check(doc, context) do
      checked
    else
      _unchecked -> doc
    end
  end

  # The sample prints beside the page, after it loads; a newer print replaces one still
  # running.
  defp preview(socket) do
    %{form: form, owner: owner, page: page, activity: activity} = socket.assigns
    activity_id = activity && activity.id

    socket
    |> assign(previewing: true)
    |> start_async(:preview, fn -> FormSample.print(form, owner, page, activity_id) end)
  end

  defp parse(text) do
    case Document.parse(text) do
      {:ok, doc} -> doc
      {:error, _error} -> nil
    end
  end

  defp page_count(page) do
    case Service.PDFPages.count(page) do
      {:ok, pages} -> pages
      :error -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item
        :if={FormOwner.settings_path(@owner)}
        label="Team settings"
        path={FormOwner.settings_path(@owner)}
      />
      <:item label="Forms" path={FormOwner.forms_path(@owner)} />
      <:item label={@form.name} />
    </.breadcrumbs>
    <h1 class="title">{@form.name}</h1>
    <p :if={@form.about} class="lead measure">{@form.about}</p>
    <p :if={@from} id="form-from" class="measure">
      {@from.short_name}'s form. Only {@from.short_name} can change it.
    </p>
    <.draft_waiting
      id="form-draft"
      draft={@draft}
      name={@form.name}
      change="Change form"
      change_path={FormOwner.change_path(@owner, @form)}
      timezone={@owner.timezone}
    />

    <div class="content-wrapper">
      <aside class="content-1/3">
        <%!-- Two switches for three states, each a step the form is ready for: Ready to try
        shows it on activities for drafts, and Ready to publish, once it's on, lets team
        admins publish. Greyed until the form is written. --%>
        <div
          :if={@own?}
          id="form-on-off"
          class="flex flex-col gap-4 pb-6 mb-6 border-b border-border-subtle"
        >
          <.switch
            id="form-on"
            label="Ready to try"
            checked={@form.state != :off}
            disabled={!Form.written?(@form)}
            phx-click="state"
            phx-value-state={if @form.state == :off, do: "testing", else: "off"}
            {off_confirm(@form)}
          >
            {try_hint(@owner, @form, @doc)}
          </.switch>
          <.switch
            :if={@form.state != :off}
            id="form-publish"
            label="Ready to publish"
            checked={@form.state == :on}
            phx-click="state"
            phx-value-state={if @form.state == :on, do: "testing", else: "on"}
            {publish_confirm(@owner, @form)}
          >
            Team admins publish it, with an ID and a verify code. Until then, draft PDFs only,
            marked DRAFT.
          </.switch>
          <%!-- It looks on, but its organization's of the same name shows instead. --%>
          <p :if={@replaced?} id="form-replaced" class="hint">
            <strong>Replaced by your organization's {@form.name}.</strong>
            Your organization's shows on your activities instead.
          </p>
        </div>
        <dl id="form-facts">
          <dt :if={@from}>State</dt>
          <dd :if={@from} id="form-state">
            {Form.state_label(@form.state)}, for every {@from.short_name} team
          </dd>
          <dt>Shows on</dt>
          <dd id="form-shows-on">{shows_on(@doc)}</dd>
          <dt>Version</dt>
          <dd id="form-version">
            {@form.version}
            <span class="hint">
              {Service.Format.date_long(@form.updated_at, @owner.timezone)}
            </span>
          </dd>
          <dt>Actions</dt>
          <dd>
            <ul id="form-actions" class="action-list">
              <li :if={@change?}>
                <.a id="form-change" navigate={FormOwner.change_path(@owner, @form)}>Change form</.a>
              </li>
              <li :if={@copy?}>
                <.a
                  id="form-copy"
                  href="#"
                  phx-click="copy"
                  phx-disable-with="Copying…"
                >Copy as your team's form</.a>
              </li>
              <li :if={@activity}>
                <.a
                  id="form-try-download"
                  href={FormOwner.try_path(@owner, @form) <> "?activity=#{@activity.id}"}
                  target="_blank"
                >Download sample PDF</.a>
              </li>
              <li :if={@page_count}>
                <.a
                  id="form-page"
                  href={FormOwner.page_path(@owner, @form)}
                  target="_blank"
                >Download agency's blank PDF</.a>
              </li>
              <li :if={@delete?}>
                <.a
                  id="form-delete"
                  href="#"
                  phx-click="delete"
                  phx-disable-with="Deleting…"
                  {Web.DeleteConfirm.form(@form)}
                >Delete form</.a>
              </li>
            </ul>
          </dd>
          <%!-- Last, since a form can ask a lot. --%>
          <dt>Questions</dt>
          <dd id="form-questions">
            <div :if={asks(@doc) == []}>None</div>
            <ul :if={asks(@doc) != []} class="list-disc pl-6">
              <li :for={ask <- asks(@doc)} class="mb-1">
                {ask.label}
                <span :if={question_line(@doc, ask, @owner)} class="hint block">
                  {question_line(@doc, ask, @owner)}
                </span>
              </li>
            </ul>
          </dd>
        </dl>
      </aside>
      <main class="content-2/3">
        <p :if={!Form.written?(@form)} id="form-not-written" class="mb-4 measure">
          {@form.name} isn't written yet.
        </p>

        <section id="form-try" class="mb-8">
          <h2 :if={Form.written?(@form)} class="heading mb-2">Sample</h2>
          <p :if={Form.written?(@form)} class="measure">{sample_lead(@owner, @own?)}</p>
          <.form_sample
            owner={@owner}
            written={Form.written?(@form)}
            activities={@activities}
            activity={@activity}
            pages={@pages}
            previewing={@previewing}
            preview_error={@preview_error}
          />
        </section>

        <details :if={Form.written?(@form)} id="form-text" class="mb-8">
          <summary class="link cursor-pointer">Show how it fills in</summary>
          <p class="measure mt-2">
            What the form reads, what it asks, and where each value goes on the page.
          </p>
          <pre class="code-block"><code>{@form.text}</code></pre>
        </details>
      </main>
    </div>
    """
  end

  # Not written yet, what comes first; else who fills it in, and from what.
  defp try_hint(owner, form, doc) do
    cond do
      !Form.written?(form) ->
        "Change form writes it first."

      match?(%Organization{}, owner) ->
        "Team admins of every #{owner.short_name} team fill it in from #{an_activity(doc)}."

      true ->
        "Team admins fill it in from #{an_activity(doc)}. Only #{owner.name} sees it."
    end
  end

  defp sample_lead(%Organization{}, _own?),
    do:
      "Printed from Coast Range SAR, a made-up team, never one of your teams' people. " <>
        "Each question's default answer."

  defp sample_lead(_team, true), do: "Each question's default answer."

  defp sample_lead(_team, false),
    do: "Tried on your own activity. Each question's default answer."

  defp off_confirm(%Form{state: :off}), do: %{}

  defp off_confirm(form),
    do: %{
      "data-confirm" => "Turn off #{form.name}? Team admins can no longer fill it in.",
      "data-confirm-button" => "Turn off"
    }

  defp publish_confirm(owner, %Form{state: :testing} = form),
    do: %{
      "data-confirm" => "Publish #{form.name}? #{who_publishes(owner)}",
      "data-confirm-button" => "Ready to publish"
    }

  defp publish_confirm(_owner, _form), do: %{}

  defp who_publishes(%Organization{}),
    do: "Team admins of every team can then publish it, with an ID and a verify code."

  defp who_publishes(_team), do: "Team admins can then publish it, with an ID and a verify code."

  # Which activities, in words: a kind's plural for `where kind = '…'`, else Some
  # activities; Show how it fills in has the rule.
  defp shows_on(nil), do: "Activities"
  defp shows_on(%Document{where: nil}), do: "Every activity"

  defp shows_on(%Document{where: {:op, :eq, {:field, ["kind"], _, _}, {:literal, kind, _}, _}})
       when kind in ~w(incident exercise event),
       do: CustomField.target_title(kind)

  defp shows_on(%Document{}), do: "Some activities"

  # What team admins fill it in from: "an incident" for a form on incidents.
  defp an_activity(%Document{where: {:op, :eq, {:field, ["kind"], _, _}, {:literal, kind, _}, _}})
       when kind in ~w(incident exercise event),
       do: "an #{kind}"

  defp an_activity(_doc), do: "an activity"

  # A question's type and how it starts: "Number, starts at 0".
  defp question_line(doc, ask, owner) do
    case Enum.reject([kind(doc, ask), each(ask), start(ask, owner)], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  defp kind(_doc, %{choices: [_ | _] = choices}), do: Service.Format.or_list(choices)
  defp kind(doc, ask), do: doc |> Document.ask_type(ask) |> type_word()

  defp type_word(:text), do: "Text"
  defp type_word(:number), do: "Number"
  defp type_word(:day), do: "Date"
  defp type_word(_unchecked), do: nil

  defp each(%{each: nil}), do: nil
  defp each(%{each: report}), do: "one on each row of #{report}"

  defp start(%{remember: true}, %Organization{}), do: "starts with the team's last answer"
  defp start(%{remember: true}, _team), do: "starts with your last answer"
  defp start(%{default: {:literal, value, _line}}, _owner), do: "starts at #{value}"
  defp start(_ask, _owner), do: nil

  defp asks(nil), do: []
  defp asks(%Document{asks: asks}), do: asks

  def handle_event("try_on", %{"activity" => id}, socket) do
    activity = Enum.find(socket.assigns.activities, &(to_string(&1.id) == id))
    {:noreply, socket |> assign(activity: activity) |> preview()}
  end

  def handle_event("state", %{"state" => state}, socket) when state in ~w(off testing on) do
    %{form: form, owner: owner, current_user: user} = socket.assigns

    case SetFormState.call(form, String.to_existing_atom(state), user) do
      {:ok, form} ->
        {:noreply, socket |> assign_form(form) |> put_flash(:info, state_message(owner, form))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer turn this form on or off.")}

      {:error, :not_written} ->
        {:noreply, put_flash(socket, :error, "Save the form's text before you turn it on.")}
    end
  end

  def handle_event("discard_draft", _params, socket) do
    %{form: form, current_user: user} = socket.assigns
    SaveDraft.discard(user, form)

    {:noreply,
     socket |> assign(draft: nil) |> put_flash(:info, "Discarded your changes to #{form.name}.")}
  end

  def handle_event("copy", _params, socket) do
    %{form: form, owner: owner, current_user: user} = socket.assigns

    case CopyForm.call(form, owner, user) do
      {:ok, copy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Copied as #{copy.name}. It's off until you turn it on.")
         |> push_navigate(to: FormOwner.form_path(owner, copy))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer copy this form.")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("delete", _params, socket) do
    %{form: form, owner: owner, current_user: user} = socket.assigns

    case DeleteForm.call(form, user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Deleted #{form.name}.")
         |> push_navigate(to: FormOwner.forms_path(owner))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can no longer delete this form.")}

      {:error, :published} ->
        {:noreply,
         put_flash(socket, :error, "Turn #{form.name} off instead. PDFs were published from it.")}
    end
  end

  defp state_message(%Organization{}, %Form{state: :on, name: name}),
    do: "#{name} turned on for every team."

  defp state_message(_team, %Form{state: :on, name: name}), do: "#{name} turned on."
  defp state_message(_owner, %Form{state: :testing, name: name}), do: "#{name} set to testing."
  defp state_message(_owner, %Form{state: :off, name: name}), do: "#{name} turned off."

  def handle_async(:preview, {:ok, printed}, socket),
    do: {:noreply, socket |> assign(printed) |> assign(previewing: false)}

  def handle_async(:preview, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, previewing: false)}
end
