defmodule App.Operation.ChangeD4HAccessKey do
  alias App.Accounts.User
  alias App.ViewModel.ChangeD4HAccessKeyViewModel

  def build_new_changeset() do
    ChangeD4HAccessKeyViewModel.build_new_changeset()
  end

  def validate(form_params) do
    ChangeD4HAccessKeyViewModel.build_new_changeset(form_params)
  end

  def call(form_params, user) do
    case ChangeD4HAccessKeyViewModel.validate(form_params) do
      {:ok, view_model} ->
        User.update(user, %{
          d4h_access_key: view_model.access_key,
          d4h_api_host: view_model.api_host,
          d4h_team_title: view_model.team_title,
          d4h_team_subdomain: view_model.team_subdomain,
          d4h_changed_at: DateTime.utc_now()
        })

      {:error, _changeset} = result ->
        result
    end
  end
end
