defmodule App.Operation.AddD4HAccessKey do
  alias App.Accounts.User
  alias App.Adapter.D4H
  alias App.Model.Team
  alias App.Repo
  alias App.Validate
  alias App.ViewModel.D4HAccessKeyViewModel

  def build_new_changeset do
    D4HAccessKeyViewModel.build_new_changeset(%{api_host: D4H.default_region()})
  end

  def validate(form_params) do
    D4HAccessKeyViewModel.build_new_changeset(form_params)
  end

  def call(form_params, user) do
    case D4HAccessKeyViewModel.validate(form_params) do
      {:ok, view_model} ->
        Repo.transaction(fn ->
          team = find_or_insert_team(view_model)

          User.update(user, %{
            team_id: team.id,
            d4h_access_key: view_model.access_key
          })
        end)

      {:error, _changeset} = result ->
        result
    end
  end

  defp find_or_insert_team(view_model) do
    d4h_team_id = view_model.d4h_team.d4h_team_id
    team = Team.get_by(%{d4h_team_id: d4h_team_id})

    if team do
      team
    else
      {lat, lng} = view_model.d4h_team.coordinate

      Team.insert!(%{
        subdomain: view_model.d4h_team.subdomain,
        d4h_team_id: d4h_team_id,
        d4h_api_host: view_model.api_host,
        name: String.slice(view_model.d4h_team.name, 0, Validate.Name.max_length()),
        mailing_address: "",
        lat: lat,
        lng: lng,
        timezone: view_model.d4h_team.timezone
      })
    end
  end
end
