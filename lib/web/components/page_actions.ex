defmodule Web.Components.PageActions do
  @moduledoc """
  A page's own actions when it has no sidebar for an Actions list, such as a report: a
  line of arrow links under the title and lead, after a byline when the page has one
  (#784). A list on the report engine ends with the same line (ReportPage). Links, never buttons: buttons stay for making something and for a form's Save.
  See /styles/page-actions.
  """
  use Web, :function_component

  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :byline, doc: "who made the page's record and when, or what the page is, in hint text"
  slot :action, required: true, doc: "one link each, in the Actions order (ActionOrderTest)"

  def page_actions(assigns) do
    ~H"""
    <div id={@id} class={["page-actions", @class]}>
      <p :for={byline <- @byline} class="hint">{render_slot(byline)}</p>
      <ul class="page-actions-list">
        <li :for={action <- @action}>{render_slot(action)}</li>
      </ul>
    </div>
    """
  end
end
