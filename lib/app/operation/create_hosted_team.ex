defmodule App.Operation.CreateHostedTeam do
  @moduledoc """
  An admin creates a team without D4H (docs/hosted-d4h.md): a hosted store with its key,
  the team's first manager as an Owner there, and the SAR Duty team pointed at the store.
  Then the first refresh copies the store, so the manager can log in at once.

  The manager is written straight into the store, not through a change set: the store
  is being set up, and SAR Duty has no D4H record to change yet.
  """

  import Ecto.Changeset

  alias App.Adapter.D4H
  alias App.Hosted
  alias App.Model.Team
  alias App.Operation.SeedHostedTeam
  alias App.Repo
  alias App.ViewModel.HostedTeamViewModel
  alias App.Worker.RefreshTeamDataWorker

  @owner 0

  def call(params, now \\ DateTime.utc_now()) do
    with {:ok, view_model} <- HostedTeamViewModel.validate(params),
         :ok <- check_subdomain(params, view_model.subdomain),
         {:ok, team} <- create(view_model, now) do
      # Run here, not queued: the manager logs in next, and the refresh queue may be busy
      # with another team. The store is in-process, so it takes a moment.
      :ok = RefreshTeamDataWorker.perform(%Oban.Job{args: %{"team_id" => team.id}})
      {:ok, Team.get!(team.id)}
    end
  end

  defp check_subdomain(params, subdomain) do
    if Team.get_by(subdomain: subdomain) || Repo.get_by(Hosted.Team, subdomain: subdomain) do
      changeset =
        params
        |> HostedTeamViewModel.build_new_changeset()
        |> add_error(:subdomain, "Another team uses this one. Choose another.")

      {:error, %{changeset | action: :insert}}
    else
      :ok
    end
  end

  defp create(view_model, now) do
    Repo.transaction(fn ->
      {:ok, hosted, key} =
        Hosted.create_team(%{
          title: view_model.name,
          subdomain: view_model.subdomain,
          timezone: view_model.timezone
        })

      {:ok, _manager} =
        Hosted.create(hosted, "members", %{
          name: view_model.manager_name,
          email: String.downcase(view_model.manager_email),
          permission: @owner,
          status: "OPERATIONAL",
          starts_at: DateTime.truncate(now, :second)
        })

      if view_model.sample_data, do: SeedHostedTeam.call(hosted, now)

      Team.insert!(%{
        name: view_model.name,
        subdomain: view_model.subdomain,
        d4h_team_id: hosted.id,
        d4h_api_host: D4H.hosted_host(),
        d4h_access_key: key,
        d4h_access_key_saved_at: now,
        mailing_address: "",
        lat: 0.0,
        lng: 0.0,
        timezone: view_model.timezone
      })
    end)
  end
end
