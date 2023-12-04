defmodule Web.AttendanceLive do
  use Web, :live_view

  alias Service.D4H

  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Attendance",
        d4h_access_token: System.get_env("D4H_ACCESS_TOKEN"),
        d4h_api_host: "api.ca.d4h.org",
        d4h_activity_id: "239224",
        activity: nil
      )

    {:ok, socket}
  end

  def render(%{:activity => activity} = assigns) when not is_nil(activity) do
    ~H"""
    <.title_block />
    <.activity_description activity={@activity} />
    <hr />
    <.activity_attendance attendance={@attendance} />
    """
  end

  def render(assigns) do
    ~H"""
    <.title_block />
    <form phx-submit="search" _phx-change="suggest">
      <div class="md:w-1/2">
        <.input
          label="D4H Access Token"
          type="password"
          name="d4h_access_token"
          value={@d4h_access_token}
          autocomplete="off"
        />
        <.input label="D4H API Host" name="d4h_api_host" value={@d4h_api_host} />
        <.input label="D4H Activity ID" name="d4h_activity_id" value={@d4h_activity_id} />
      </div>
      <.button class="btn-success">Look up event</.button>
    </form>
    """
  end

  def activity_description(assigns) do
    ~H"""
    <section>
      <h2 class="heading"><%= @activity.title %></h2>
      <pre class="my-4 text-sm"><%= inspect(@activity, pretty: true) %></pre>
    </section>
    """
  end

  def activity_attendance(assigns) do
    ~H"""
    <section>
      <h2 class="subheading">Attendance</h2>
      <pre class="my-4 text-sm"><%= inspect(@attendance, pretty: true) %></pre>
    </section>
    """
  end

  def title_block(assigns) do
    ~H"""
    <hgroup class="mb-8">
      <h1 class="title">Attendance</h1>
      <p class="lead">
        Synchronize activity attendance to D4H from SAR Assist.
      </p>
    </hgroup>
    """
  end

  def handle_event("search", params, socket) do
    d4h_activity_id = params["d4h_activity_id"]

    config = D4H.build_config()
    activity = D4H.fetch_activity!(config, d4h_activity_id)
    attendance = D4H.fetch_attendance!(config, d4h_activity_id)

    socket =
      assign(
        socket,
        d4h_activity_id: d4h_activity_id,
        activity: activity,
        attendance: attendance
      )

    {:noreply, socket}
  end
end
