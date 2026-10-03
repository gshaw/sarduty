defmodule Web.StyleGuide.FormsLive do
  use Web, :live_view_marketing_layout

  import Web.Components.StyleGuide

  alias Web.StyleGuide.SampleData

  def mount(_params, _session, socket) do
    team = %{
      "name" => "Squamish SAR",
      "lat" => "49.7553",
      "lng" => "-123.1311",
      "timezone" => "America/Vancouver",
      "mailing_address" => "PO Box 123\nSquamish BC V8B 0A1",
      "authorized_by_name" => "",
      "new_d4h_access_key" => ""
    }

    socket =
      socket
      |> assign(:page_title, "Style Guide: Forms")
      |> assign(:form, to_form(team, as: :team))

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <.style_guide_header current={:forms} />

    <.style_group id="group-rules" title="Group qualification rules">
      <p class="text-secondary-1 mb-p">
        Define which qualifications members must hold to belong to this group.
      </p>

      <div :for={clause <- SampleData.clauses()} class="mb-p border rounded px-p py-p05">
        <div class="flex justify-between items-center mb-p05">
          <form class="flex items-center gap-2">
            <input
              type="text"
              name="name"
              value={clause.name}
              placeholder="Name, e.g. First Aid"
              aria-label="Clause name"
              class="rounded border shadow-sm text-sm font-semibold"
            />
            <h3 class="font-semibold">— member must hold ANY of:</h3>
          </form>
          <.button variant={:danger} size={:sm} class="ml-p">Delete clause</.button>
        </div>

        <div class="flex flex-wrap gap-2 mb-p05">
          <span
            :for={q <- clause.qualifications}
            class={[
              "inline-flex items-center gap-2 rounded px-2 py-1 text-sm",
              if(String.starts_with?(q, "Missing"),
                do: "border border-danger-1 text-danger-1",
                else: "bg-base-2"
              )
            ]}
          >
            {q}
            <button class="text-danger-1 hover:text-danger-2 font-bold" title="Remove">
              &times;
            </button>
          </span>
          <span :if={clause.qualifications == []} class="text-secondary-1 text-sm italic">
            No qualifications added yet
          </span>
        </div>

        <form class="flex gap-2 items-end">
          <select
            name="qualification-id"
            class="block rounded border shadow-sm text-sm max-w-xs truncate"
          >
            <option value="">Add qualification...</option>
            <option>Rope Rescue Technician</option>
            <option>Swiftwater Rescue</option>
          </select>
          <.button type="button" size={:sm}>Add</.button>
        </form>
      </div>

      <div class="flex gap-2">
        <.button size={:sm}>+ Add clause</.button>
        <.button variant={:primary} size={:sm}>Done</.button>
      </div>

      <div class="mt-p">
        <h2 class="subheading mb-p05">Rule Preview</h2>
        <p class="rounded bg-warning-1 text-warning-content px-p py-p05 text-sm">
          These rules name a qualification that is no longer in D4H. Edit the rules to
          remove or replace it, then the preview comes back.
        </p>
        <.change_list
          id="would-remove"
          title="Would be removed"
          title_class="text-danger-1"
          rows={SampleData.preview().to_remove}
        />
        <.change_list
          id="would-add"
          title="Would be added"
          title_class="text-success-1"
          rows={SampleData.preview().to_add}
        />
        <.change_list
          id="expiring"
          title="Expiring within 30 days"
          title_class="text-base-content"
          rows={SampleData.preview().expiring}
        />
        <.button variant={:primary} navigate={~p"/styles/forms"}>Review changes</.button>
      </div>
    </.style_group>

    <.style_group id="import-attendance" title="Import attendance">
      <form>
        <.input
          type="textarea"
          name="import_content"
          value=""
          label="Attendance record report"
          class="h-[16rem]"
        >
          Copy and paste the attendance report into this text area.
          Members will be matched by their name, email, or phone in D4H.
          You will have a chance to review changes before they are performed.
        </.input>
        <.button type="button" variant={:success}>Import Attendance Report</.button>
      </form>
    </.style_group>

    <.style_group id="team-settings" title="Team settings">
      <.form for={@form} id="team_settings_form">
        <.input field={@form[:name]} label="Name" />
        <div class="grid grid-cols-2 gap-hspacer">
          <.input field={@form[:lat]} readonly label="Lat" class="bg-base-3" />
          <.input field={@form[:lng]} readonly label="Lng" class="bg-base-3" />
        </div>
        <.input field={@form[:timezone]} label="Timezone" readonly class="bg-base-3" />
        <.input
          field={@form[:mailing_address]}
          label="Mailing address"
          type="textarea"
          class="h-[10rem]"
        />
        <.input
          field={@form[:authorized_by_name]}
          label="Tax letters authorized by"
          type="textarea"
          class="h-[10rem]"
          errors={["can't be blank"]}
        >
          Should include full name, title, team address, and phone number of the team president or other
          individual with a similar role from the organization. Used by CRA during tax audits.
        </.input>
        <.input
          field={@form[:new_d4h_access_key]}
          label="D4H access key (team)"
          type="password"
          autocomplete="off"
        >
          SAR Duty uses this one key for every D4H request. A key is saved.
        </.input>
        <div class="mb-p text-sm">
          <p class="rounded bg-warning-1 text-warning-content px-p py-p05">
            Create the key from a D4H member named "SAR Duty" rather than a person.
          </p>
        </div>
        <.form_actions>
          <.button type="button" variant={:success}>Save</.button>
          <:trailing>
            <.button type="button">Refresh from D4H</.button>
          </:trailing>
        </.form_actions>
      </.form>
    </.style_group>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :title_class, :string, required: true
  attr :rows, :list, required: true

  # A copy of the change list on the group page.
  defp change_list(assigns) do
    ~H"""
    <div :if={@rows != []} class="mb-p">
      <h3 class={["font-semibold mb-p05", @title_class]}>{@title} ({length(@rows)})</h3>
      <.table id={@id} rows={@rows} class="w-full table-striped">
        <:col :let={row} label="Member" class="md:w-1/3">
          <.a navigate={~p"/styles/forms"}>{row.name}</.a>
        </:col>
        <:col :let={row} label="Why">
          {row.reason}
          <.badge :if={row[:days]} kind={:warning} class="ml-2 whitespace-nowrap">
            {row.days} days
          </.badge>
        </:col>
      </.table>
    </div>
    """
  end
end
