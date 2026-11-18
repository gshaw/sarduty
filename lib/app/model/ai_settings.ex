defmodule App.Model.AISettings do
  @moduledoc """
  SAR Duty's AI writing settings: one row, changed only on Adminland › AI writing
  (App.Operation.SetAISettings). `access` says who gets AI writing: nobody, SAR Duty
  admins only while it's tried, or every team admin. `report_model` and `form_model` are
  the Claude models each kind of ask uses: forms are harder, so they start on Opus.
  `monthly_budget_cents` stops asks once this month's asks cost that much
  (App.Model.AIAsk.month_cost_microdollars/1). `report_next_asks` and `form_next_asks`
  are how many next asks AI suggests after each reply, 0 to 4. With no row yet, AI
  writing is off.
  """
  use App, :model

  alias App.Accounts.User
  alias App.AI.Models
  alias App.Model.AISettings
  alias App.Repo

  @accesses ~w(off admins everyone)
  @fields [
    :access,
    :report_model,
    :form_model,
    :monthly_budget_cents,
    :report_next_asks,
    :form_next_asks
  ]
  @most_next_asks 4

  schema "ai_settings" do
    field :access, :string, default: "off"
    field :report_model, :string, default: "claude-sonnet-5-5"
    field :form_model, :string, default: "claude-opus-5-5"
    field :monthly_budget_cents, :integer, default: 5_000
    field :report_next_asks, :integer, default: 2
    field :form_next_asks, :integer, default: 2
    belongs_to :updated_by, User
    timestamps(type: :utc_datetime_usec)
  end

  def accesses, do: @accesses
  def most_next_asks, do: @most_next_asks

  @doc """
  The settings, or the defaults when nobody has saved any: off, Sonnet for reports and
  Opus for forms, two next asks each, $50.
  """
  def get, do: AISettings |> order_by([s], s.id) |> limit(1) |> Repo.one() || %AISettings{}

  @doc "For Adminland's form. The budget is in whole dollars there."
  def changeset(%AISettings{} = settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_inclusion(:access, @accesses)
    |> validate_inclusion(:report_model, Models.ids())
    |> validate_inclusion(:form_model, Models.ids())
    |> validate_number(:monthly_budget_cents, greater_than_or_equal_to: 0)
    |> validate_number(:report_next_asks,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @most_next_asks
    )
    |> validate_number(:form_next_asks,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @most_next_asks
    )
  end

  @doc "The model a job of `kind` uses: a form's, or a report's for the rest, such as a History line."
  def model(%AISettings{form_model: model}, :form), do: model
  def model(%AISettings{report_model: model}, _kind), do: model

  @doc "How many next asks AI suggests after a reply to a job of `kind`: 0 for none."
  def next_asks(%AISettings{report_next_asks: n}, :report), do: n
  def next_asks(%AISettings{form_next_asks: n}, :form), do: n
  def next_asks(%AISettings{}, _kind), do: 0

  @doc "Whether `user` gets AI writing under these settings, before the key and the budget."
  def open_to?(%AISettings{access: "everyone"}, %User{}), do: true
  def open_to?(%AISettings{access: "admins"}, %User{is_admin: admin?}), do: admin?
  def open_to?(%AISettings{}, _user), do: false
end
