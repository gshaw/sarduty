defmodule Web.StyleGuide.TablesLive do
  use Web, :live_view_marketing_layout

  import Web.Components.StyleGuide

  # cspell:ignore Dhillon Tremblay

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Style Guide: Tables")}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:sort, params["sort"] || "total")
      |> assign(:path_fn, &path/1)

    {:noreply, socket}
  end

  defp path(:reset), do: ~p"/styles/tables"
  defp path(opts), do: ~p"/styles/tables?#{Keyword.take(opts, [:sort])}"

  def render(assigns) do
    ~H"""
    <.style_guide_header current={:tables} />

    <.style_group id="tax-credit-letters" title="Tax credit letters">
      <p>Filter form, summary line, a grouped header row, sortable columns, and an action column.</p>
      <form id="tax_credit_letter_filter_form" class="filter-form">
        <.input label="Year" name="year" value="2025" type="select" options={["2025", "2024"]} />
        <.input label="Search" name="q" value="" />
        <.input
          label="Sort"
          name="sort"
          value="total"
          type="select"
          options={[{"Total hours", "total"}, {"Name", "name"}]}
        />
        <.input
          label="Hours"
          name="filter"
          value="200"
          type="select"
          options={[{"200 hours or more", "200"}, {"Everyone", "all"}]}
        />
      </form>

      <div class="table-summary">
        <span class="table-summary-links">
          <.a navigate={@path_fn.(:reset)}>Reset</.a>
        </span>
        <span class="table-summary-count">{length(letters())} members</span>
      </div>

      <.table
        id="letters"
        rows={letters()}
        sort={@sort}
        path_fn={@path_fn}
        class="w-full table-striped"
      >
        <:header_row>
          <th colspan="3"></th>
          <th colspan="3" class="text-center">SARVAC Hours</th>
          <th></th>
        </:header_row>
        <:col :let={r} label="ID" class="w-px" sorts={[{"↑", "id"}]}>{r.id}</:col>
        <:col :let={r} label="Name" sorts={[{"↑", "name"}]}>
          <.a navigate={~p"/styles/tables"}>{r.name}</.a>
        </:col>
        <:col :let={r} label="Email">{r.email}</:col>
        <:col
          :let={r}
          label="Primary"
          align="right"
          class="w-px whitespace-nowrap tabular-nums"
          sorts={[{"↓", "primary"}]}
        >
          {r.primary}
        </:col>
        <:col
          :let={r}
          label="Secondary"
          align="right"
          class="w-px whitespace-nowrap tabular-nums"
          sorts={[{"↓", "secondary"}]}
        >
          {r.secondary}
        </:col>
        <:col
          :let={r}
          label="Total"
          align="right"
          class="w-px whitespace-nowrap tabular-nums"
          sorts={[{"↓", "total"}]}
        >
          {r.total}
        </:col>
        <:col :let={r} label="Letter" class="whitespace-nowrap">
          <.a :if={r.letter} navigate={~p"/styles/tables"}>
            <span class="font-mono text-sm">{r.letter}</span>
          </.a>
          <.button :if={!r.letter} variant={:success} size={:sm}>Create letter</.button>
        </:col>
      </.table>
    </.style_group>

    <.style_group id="recommendations" title="Attendance recommendations">
      <p>A checkbox per row, a status column, and actions under the table.</p>
      <form>
        <.table id="recommendation_rows" rows={recommendations()} class="table-striped">
          <:col :let={r} label="">
            <.input :if={r.op != :not_invited} type="checkbox" name={"r#{r.phone}"} checked />
          </:col>
          <:col :let={r} label="">
            <span
              :if={r.op == :not_invited}
              class="text-danger-content font-bold bg-danger-1 rounded px-2 py-1"
            >
              Not Invited
            </span>
            <span :if={r.op == :add} class="text-success-1 font-bold">Add</span>
            <span :if={r.op == :remove} class="text-danger-1 font-bold">Remove</span>
          </:col>
          <:col :let={r} label="Name">{r.name}</:col>
          <:col :let={r} label="Email">{r.email}</:col>
          <:col :let={r} label="Phone">{r.phone}</:col>
        </.table>
        <.form_actions class="mt-4">
          <.button type="button" variant={:success}>Perform Checked Recommendations</.button>
          <.button type="button">Reset</.button>
        </.form_actions>
      </form>
    </.style_group>
    """
  end

  defp letters do
    [
      %{
        id: 101,
        name: "Avery Chen",
        email: "avery@example.com",
        primary: "212h 30m",
        secondary: "18h 00m",
        total: "230h 30m",
        letter: "TCL-2025-014"
      },
      %{
        id: 117,
        name: "Blake Morrison",
        email: "blake@example.com",
        primary: "198h 15m",
        secondary: "4h 45m",
        total: "203h 00m",
        letter: nil
      },
      %{
        id: 123,
        name: "Casey Dhillon",
        email: "casey@example.com",
        primary: "156h 00m",
        secondary: "62h 30m",
        total: "218h 30m",
        letter: "TCL-2025-015"
      },
      %{
        id: 131,
        name: "Devon Okafor",
        email: "devon@example.com",
        primary: "88h 45m",
        secondary: "12h 15m",
        total: "101h 00m",
        letter: nil
      },
      %{
        id: 152,
        name: "Finley Tremblay",
        email: "finley@example.com",
        primary: "41h 00m",
        secondary: "9h 30m",
        total: "50h 30m",
        letter: nil
      }
    ]
  end

  defp recommendations do
    [
      %{op: :add, name: "Avery Chen", email: "avery@example.com", phone: "604-555-0101"},
      %{op: :add, name: "Casey Dhillon", email: "casey@example.com", phone: "604-555-0123"},
      %{op: :remove, name: "Devon Okafor", email: "devon@example.com", phone: "604-555-0131"},
      %{op: :not_invited, name: "Jordan Park", email: "jordan@example.com", phone: "604-555-0177"}
    ]
  end
end
