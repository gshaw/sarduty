defmodule Web.Components.AttendanceImport do
  @moduledoc """
  Import attendance on an activity: the form that takes a pasted SAR Assist report, and
  the recommended changes to review before SAR Duty sends them to D4H. The style guide's
  Paste a report and Review changes patterns render these with made-up members.
  """
  use Phoenix.Component

  import Web.Components.Core, only: [badge: 1, button: 1, form_actions: 1, input: 1]
  import Web.Components.Table

  attr :value, :string, default: ""

  def paste_report(assigns) do
    ~H"""
    <form phx-submit="import-attendance">
      <.input
        type="textarea"
        id="import_content"
        name="import_content"
        value={@value}
        label="Attendance report"
        rows="10"
      >
        Paste the attendance report here. SAR Duty matches members by their name, email, or
        phone in D4H. You review the changes before SAR Duty makes them.
      </.input>
      <.button variant={:success}>Import attendance</.button>
    </form>
    """
  end

  attr :rows, :list, required: true, doc: "{:add | :remove | :not_invited, id, member}"

  # Every change starts checked. A member who did not sign up has no checkbox.
  def recommended_changes(assigns) do
    ~H"""
    <form phx-submit="perform-recommendations">
      <.table id="recommendations" rows={@rows} class="table-striped table-stack">
        <:col :let={{_op, attendance_id, _member}} label="" class="stack-check">
          <.input :if={attendance_id} type="checkbox" name={attendance_id} checked />
        </:col>
        <:col :let={{op, _, _}} label="" class="stack-full">
          <.badge :if={op == :not_invited} kind={:danger}>Not signed up</.badge>
          <strong :if={op == :add} class="text-success-text">Add</strong>
          <strong :if={op == :remove} class="text-danger-text">Remove</strong>
        </:col>
        <:col :let={{_, _, member}} label="Name" class="stack-title">{member.name}</:col>
        <:col :let={{_, _, member}} label="Email" class="stack-full break-all">
          {member.email}
        </:col>
        <:col :let={{_, _, member}} label="Phone">{member.phone}</:col>
      </.table>
      <.form_actions>
        <.button disabled={!Enum.any?(@rows, &(elem(&1, 0) in [:add, :remove]))} variant={:success}>
          Perform checked changes
        </.button>
        <.button type="button" phx-click="reset">Start over</.button>
      </.form_actions>
    </form>
    """
  end
end
