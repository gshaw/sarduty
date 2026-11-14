defmodule Web.MeFieldsLive do
  use Web, {:live_view_app_layout, access: :member, view_events: ["validate"]}

  import Web.Components.CustomFields
  import Web.MemberLogin

  alias App.Model.CustomField
  alias App.Operation.SaveOwnDetails

  # Change fields (#1056), /teams/:subdomain/me/fields: the member fields D4H lets a member
  # see (#681). The ones D4H sets to `editable` are inputs, saved straight to D4H; the
  # `viewable` ones are read only under them. A key that can't fill in fields shows them
  # all read only. A team admin viewing as the member (#425) sees the page with saving
  # turned off.
  def mount(_params, _session, socket) do
    member = socket.assigns.current_member
    editable = SaveOwnDetails.fields(member)
    ids = MapSet.new(editable, & &1.id)

    read_only =
      member.team_id
      |> CustomField.member_fields(:self)
      |> Enum.reject(&MapSet.member?(ids, &1.id))

    socket =
      assign(socket,
        page_title: "Change fields",
        editable_fields: editable,
        values: member.custom_values || %{},
        field_rows: CustomField.rows(read_only, member.custom_values, member.team.timezone)
      )

    {:ok, socket}
  end

  # Keeps what was typed when the page renders again, such as after D4H refuses.
  def handle_event("validate", params, socket),
    do: {:noreply, keep_values(socket, params)}

  def handle_event("save", params, socket) do
    socket = keep_values(socket, params)
    values = %{"fields" => params["fields"] || %{}}

    {:noreply,
     with_login(socket, fn member ->
       case SaveOwnDetails.call(member, socket.assigns.current_user, values, DateTime.utc_now()) do
         {:ok, _result} ->
           socket
           |> put_flash(:info, "Your fields are saved.")
           |> push_navigate(to: ~p"/teams/#{member.team}/me")

         {:error, text} ->
           put_flash(socket, :error, text)
       end
     end)}
  end

  defp keep_values(socket, params),
    do: update(socket, :values, &Map.merge(&1, params["fields"] || %{}))

  def render(assigns) do
    ~H"""
    <.breadcrumbs>
      <:item label="Your membership" path={~p"/teams/#{@current_member.team}/me"} />
      <:item label="Change fields" />
    </.breadcrumbs>
    <div class="measure">
      <h1 class="title">Change fields</h1>
      <p class="lead">Changes go to your team's records, where your team admins see them.</p>
      <.form
        :if={@editable_fields != []}
        for={%{}}
        as={:fields}
        id="fields-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.custom_field_inputs fields={@editable_fields} values={@values} />
        <.form_actions>
          <.button variant={:success} phx-disable-with="Saving…" disabled={@viewing_as != nil}>
            Save fields
          </.button>
          <.button navigate={~p"/teams/#{@current_member.team}/me"}>Cancel</.button>
        </.form_actions>
      </.form>
      <.custom_fields
        id="own-fields"
        rows={@field_rows}
        class={if @editable_fields != [], do: "mt-8", else: ""}
      />
    </div>
    """
  end
end
