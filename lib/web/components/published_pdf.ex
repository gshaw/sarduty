defmodule Web.Components.PublishedPDF do
  @moduledoc """
  The parts a published PDF's page shares, a letter's and a form's (#970): Out of date
  with what changed, page 1 as a picture, History, and Withdraw's confirm.
  """
  use Web, :function_component

  import Web.Components.A
  import Web.Components.Table

  alias App.Model.PublishedPDF

  attr :id, :string, required: true
  attr :noun, :string, required: true, doc: "what reads differently: \"letter\", \"form\""
  attr :changes, :list, required: true, doc: "a line for each value that changed"

  def out_of_date(assigns) do
    ~H"""
    <div :if={@changes != []} id={@id} class="callout mb-4">
      <p class="mb-1"><b>Out of date.</b> The {@noun} reads differently now:</p>
      <ul>
        <li :for={change <- @changes}>{change}</li>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :alt, :string, required: true

  # Drawn from the PDF when the page asks (Web.PublishedPDFController.preview/2).
  def preview(assigns) do
    ~H"""
    <img
      id={@id}
      src={@src}
      alt={@alt}
      loading="lazy"
      class="w-full max-w-xl mb-8 border border-border-subtle shadow-sm"
    />
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true, doc: "App.ViewData.PublishedHistory.rows/2's"
  attr :team, :map, required: true

  def history(assigns) do
    ~H"""
    <section :if={@rows != []} id={@id} class="mb-8">
      <h2 class="heading">History</h2>
      <.table id={"#{@id}-table"} rows={@rows} row_id={&row_id(@id, &1)} class="table-striped">
        <:col :let={row} label="When" class="w-px whitespace-nowrap">
          {row.at && Service.Format.datetime_short(row.at, @team.timezone)}
        </:col>
        <:col :let={row} label="What">
          {what(row.what)}
          <.a href={~p"/teams/#{@team}/pdfs/#{row.pdf.id}"} target="_blank" class="mono">{PublishedPDF.format_code(
            row.pdf.code
          )}</.a>
          <.status_badge :if={row.what in [:published, :published_again]} pdf={row.pdf} />
        </:col>
        <:col :let={row} label="By">{row.by}</:col>
      </.table>
    </section>
    """
  end

  attr :pdf, :map, required: true

  defp status_badge(assigns) do
    ~H"""
    <.badge :if={PublishedPDF.status(@pdf) == :replaced} kind={:warning}>Replaced</.badge>
    <.badge :if={PublishedPDF.status(@pdf) == :withdrawn} kind={:danger}>Withdrawn</.badge>
    """
  end

  defp what(:published), do: "Published"
  defp what(:published_again), do: "Published again:"
  defp what(:emailed), do: "Emailed"
  defp what(:withdrawn), do: "Withdrew"

  defp row_id(id, row), do: "#{id}-#{row.what}-#{row.pdf.id}"

  @doc """
  Withdraw's confirm, the same on every published PDF: nothing takes its place, so the
  box must be ticked. `button` is the button's words.
  """
  def withdraw_confirm(%PublishedPDF{code: code}, button) do
    code = PublishedPDF.format_code(code)

    %{
      "data-confirm" => "Withdraw #{code}? Nothing takes its place.",
      "data-confirm-warning" =>
        "Anyone holding a copy will see it was withdrawn on its verify page.",
      "data-confirm-check" => "I understand #{code} no longer verifies.",
      "data-confirm-button" => button
    }
  end
end
