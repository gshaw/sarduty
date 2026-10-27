defmodule Web.Settings.PlaceCollectionLive do
  use Web, :live_view_app_layout

  import Web.Components.TeamSettingsTabs

  alias App.Adapter.D4H
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.LocationBookmark

  # The team's saved places (#614), /teams/:subdomain/settings/places: its location
  # bookmarks, which name places in the activity form's Address list. A Records team
  # adds and changes them here. D4H's API only reads them, so a D4H team changes them in
  # D4H.
  def mount(_params, _session, socket) do
    team = socket.assigns.current_team

    socket =
      socket
      |> assign(page_title: "Team settings · Places", records?: D4H.records?(team))
      |> assign(places: LocationBookmark.get_all(team))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.team_settings_tabs team={@current_team} current={:places} />
    <.heading_row>
      <p class="lead measure">
        Places your team uses, by name. The Address box on an activity finds them by name, and shows the name for an address within 150 m.
      </p>
      <:action :if={@records?}>
        <.button
          id="place-add"
          variant={:success}
          navigate={~p"/teams/#{@current_team}/settings/places/new"}
        >
          Add place
        </.button>
      </:action>
    </.heading_row>

    <p :if={!@records?} id="places-in-service" class="measure mb-6">
      These are your team's location bookmarks in {@service}. {@service} does not let SAR Duty change them, so add or change them in {@service}. SAR Duty follows within 10 minutes.
    </p>

    <.table
      :if={@places != []}
      id="places"
      rows={@places}
      row_id={&"place-#{&1.id}"}
      class="table-striped table-stack"
    >
      <:col :let={place} label="Name" class="stack-title">
        <.a :if={@records?} navigate={~p"/teams/#{@current_team}/settings/places/#{place.id}"}>{place.title}</.a>
        <span :if={!@records?}>{place.title}</span>
      </:col>
      <:col :let={place} label="Address">{place.address}</:col>
      <:col :let={place} label="Latitude and longitude">
        {pin(place)}
      </:col>
    </.table>

    <.empty_state :if={@places == []} id="no-places" title="No places yet">
      {if @records?,
        do: "Add the places your team goes often, such as its hall.",
        else: "Add location bookmarks in #{@service} to name the places your team goes often."}
    </.empty_state>
    """
  end

  defp pin(place) do
    case place |> Activity.pin() |> Coordinate.build() do
      nil -> "None"
      pin -> Service.Format.coordinate(pin, 5)
    end
  end
end
