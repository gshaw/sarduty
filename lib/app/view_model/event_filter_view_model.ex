defmodule App.ViewModel.EventFilterViewModel do
  use App, :view_model

  alias App.Model.Event

  @primary_key false
  embedded_schema do
    field :kind, :string, default: "all"
    field :team, :string, default: "all"
    field :ip, App.Field.TrimmedString
  end

  def kinds, do: [{"All", "all"} | Enum.map(Event.kinds(), &{label(&1), Atom.to_string(&1)})]

  def teams(teams), do: [{"All", "all"} | Enum.map(teams, &{&1.name, Integer.to_string(&1.id)})]

  def label(:d4h_sync_round), do: "Sync round"
  def label(:d4h_refresh_run), do: "Nightly refresh"
  def label(:d4h_team_sync), do: "Team sync"
  def label(:d4h_team_refresh), do: "Team refresh"
  def label(:d4h_rate_limited), do: "D4H rate limit"
  def label(:login_code_requested), do: "Login code asked for"
  def label(:login_code_limited), do: "Login code limit reached"
  def label(:login_code_missed), do: "Wrong login code"
  def label(:login_blocked), do: "Login blocked"
  def label(:logged_in), do: "Logged in"
  def label(:logged_out), do: "Logged out"
  def label(:verify_limit_reached), do: "Verify limit reached"
  def label(:team_signup_failed), do: "Sign-up failed"
  def label(:team_signed_up), do: "Team signed up"
  def label(:team_key_changed), do: "D4H access key changed"
  def label(:login_grant_added), do: "Login grant added"
  def label(:login_grant_removed), do: "Login grant removed"
  def label(:tax_credit_letters_sent), do: "Tax credit letters sent"
  def label(:mcp_turned_on), do: "MCP turned on"
  def label(:mcp_turned_off), do: "MCP turned off"
  def label(:mcp_token_created), do: "MCP token created"
  def label(:mcp_token_revoked), do: "MCP token revoked"

  def validate(params) do
    changeset =
      %__MODULE__{}
      |> cast(params, [:kind, :team, :ip])
      |> validate_inclusion(:kind, Enum.map(kinds(), &elem(&1, 1)))
      |> validate_format(:team, ~r/\A(all|\d+)\z/)
      |> validate_format(:ip, ~r/\A[0-9a-fA-F.:]{1,45}\z/)

    case apply_action(changeset, :replace) do
      {:ok, filter} -> {:ok, filter, changeset}
      {:error, _} = result -> result
    end
  end

  @doc "The filter as `Event.get_recent/2` takes it."
  def to_query(%__MODULE__{kind: kind, team: team, ip: ip}) do
    %{
      kind: if(kind != "all", do: Enum.find(Event.kinds(), &(Atom.to_string(&1) == kind))),
      team_id: if(team != "all", do: String.to_integer(team)),
      ip: ip
    }
  end

  @doc "Query params for a path, leaving out the defaults."
  def to_params(%__MODULE__{} = filter) do
    filter
    |> Map.take([:kind, :team, :ip])
    |> Enum.reject(fn {_key, value} -> value in ["all", nil] end)
  end
end
