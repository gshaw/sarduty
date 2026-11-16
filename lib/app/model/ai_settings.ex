defmodule App.Model.AISettings do
  @moduledoc """
  SAR Duty's AI writing settings: one row, changed only on Adminland › AI writing
  (App.Operation.SetAISettings). `access` says who gets AI writing: nobody, SAR Duty
  admins only while it's tried, or every team admin. `model` is the Claude model asks
  use. `monthly_budget_cents` stops asks once this month's asks cost that much
  (App.Model.AIAsk.month_cost_microdollars/1). `suggest_reports` and `suggest_forms` say
  whether AI suggests next asks after each reply on each. With no row yet, AI writing
  is off.
  """
  use App, :model

  alias App.Accounts.User
  alias App.AI.Models
  alias App.Model.AISettings
  alias App.Repo

  @accesses ~w(off admins everyone)
  @default_budget_cents 5_000

  schema "ai_settings" do
    field :access, :string, default: "off"
    field :model, :string
    field :monthly_budget_cents, :integer
    field :suggest_reports, :boolean, default: true
    field :suggest_forms, :boolean, default: true
    belongs_to :updated_by, User
    timestamps(type: :utc_datetime_usec)
  end

  def accesses, do: @accesses

  @doc "The settings, or the defaults when nobody has saved any: off, the default model, $50."
  def get do
    case AISettings |> order_by([s], s.id) |> limit(1) |> Repo.one() do
      nil ->
        %AISettings{
          access: "off",
          model: Models.default(),
          monthly_budget_cents: @default_budget_cents
        }

      settings ->
        settings
    end
  end

  @doc "For Adminland's form. The budget is in whole dollars there."
  def changeset(%AISettings{} = settings, attrs) do
    settings
    |> cast(attrs, [:access, :model, :monthly_budget_cents, :suggest_reports, :suggest_forms])
    |> validate_required([:access, :model, :monthly_budget_cents])
    |> validate_inclusion(:access, @accesses)
    |> validate_inclusion(:model, Models.ids())
    |> validate_number(:monthly_budget_cents, greater_than_or_equal_to: 0)
  end

  @doc "Whether AI suggests next asks after a reply to a job of `kind`."
  def suggest?(%AISettings{suggest_reports: on}, :report), do: on
  def suggest?(%AISettings{suggest_forms: on}, :form), do: on
  def suggest?(%AISettings{}, _kind), do: false

  @doc "Whether `user` gets AI writing under these settings, before the key and the budget."
  def open_to?(%AISettings{access: "everyone"}, %User{}), do: true
  def open_to?(%AISettings{access: "admins"}, %User{is_admin: admin?}), do: admin?
  def open_to?(%AISettings{}, _user), do: false
end
