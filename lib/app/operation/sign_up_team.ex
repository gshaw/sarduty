defmodule App.Operation.SignUpTeam do
  @moduledoc """
  Self-service team sign-up (#57 phase 5). A D4H personal access token becomes the team
  key. The person signing up must be a current Owner or Editor on that team in D4H, at
  the email they give, and the team must be new to SAR Duty. Then the team goes live, its
  first refresh starts, the admins get an email, and the signer gets a login link.
  """

  import Ecto.Changeset

  alias App.Accounts
  alias App.Accounts.UserNotifier
  alias App.Adapter.D4H
  alias App.Model.Member
  alias App.Model.Team
  alias App.Repo
  alias App.Validate
  alias App.ViewModel.TeamSignupViewModel
  alias App.Worker.RefreshTeamDataWorker

  @manager_permissions [0, 1]

  def call(params, login_url_fun) do
    with {:ok, view_model} <- TeamSignupViewModel.validate(params),
         {:ok, whoami, d4h_team, signer} <- check_with_d4h(view_model) do
      {:ok, go_live(view_model, whoami, d4h_team, signer, login_url_fun)}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, {field, message}} -> {:error, form_error(params, field, message)}
    end
  end

  defp check_with_d4h(view_model) do
    with {:ok, whoami} <- fetch_whoami(view_model),
         d4h = context(view_model, whoami.d4h_team_id),
         {:ok, d4h_team} <- fetch_team(d4h),
         members = D4H.fetch_team_members(d4h),
         existing = Team.get_by(d4h_team_id: whoami.d4h_team_id),
         {:ok, signer} <- check(view_model.email, d4h_team, members, existing, DateTime.utc_now()) do
      {:ok, whoami, d4h_team, signer}
    end
  end

  defp go_live(view_model, whoami, d4h_team, signer, login_url_fun) do
    team = create_team(view_model, whoami, d4h_team, signer)
    %{team_id: team.id} |> RefreshTeamDataWorker.new() |> Oban.insert!()
    UserNotifier.deliver_team_signed_up(Accounts.admin_emails(), team, view_model.email)
    Accounts.deliver_login_link(view_model.email, login_url_fun)
    team
  end

  @doc """
  Whether this email may sign the team up: it isn't on SAR Duty yet, and the email
  belongs to one of its current D4H Owners or Editors. Returns that member, or the
  form field and message to show.
  """
  def check(email, d4h_team, members, existing_team, now) do
    email = email |> String.trim() |> String.downcase()
    signer = Enum.find(members, &(String.downcase(&1.email || "") == email))

    cond do
      existing_team ->
        {:error,
         {:access_key,
          "#{d4h_team.name} is already on SAR Duty. Its Owners and Editors can log in."}}

      signer == nil ->
        {:error,
         {:email, "Enter the email D4H has for you. No member of #{d4h_team.name} uses this one."}}

      not manager?(signer, now) ->
        {:error, {:email, "Use the email of an Owner or Editor of #{d4h_team.name} in D4H."}}

      true ->
        {:ok, signer}
    end
  end

  defp manager?(member, now) do
    member.permission in @manager_permissions and member.status != "RETIRED" and
      (is_nil(member.left_at) or DateTime.after?(member.left_at, now))
  end

  defp fetch_whoami(view_model) do
    case D4H.fetch_whoami(access_key: view_model.access_key, api_host: view_model.api_host) do
      {:ok, whoami} ->
        {:ok, whoami}

      {:error, _reason} ->
        {:error, {:access_key, "Enter a D4H access key that works in this region."}}
    end
  rescue
    Req.TransportError ->
      {:error, {:access_key, "D4H did not respond. Try again in a few minutes."}}
  end

  defp fetch_team(d4h) do
    case D4H.fetch_team(d4h) do
      {:ok, d4h_team} -> {:ok, d4h_team}
      {:error, _response} -> {:error, {:access_key, "Use a key that can read the team in D4H."}}
    end
  end

  defp context(view_model, d4h_team_id) do
    D4H.build_context(
      access_key: view_model.access_key,
      api_host: view_model.api_host,
      d4h_team_id: d4h_team_id
    )
  end

  # The team, keyed by the token, and the signer as its first member, so the login link
  # can go out before the first refresh fills in everyone else.
  defp create_team(view_model, whoami, d4h_team, signer) do
    {lat, lng} = d4h_team.coordinate || {0.0, 0.0}

    Repo.transaction(fn ->
      team =
        Team.insert!(%{
          name: String.slice(d4h_team.name, 0, Validate.Name.max_length()),
          subdomain: d4h_team.subdomain,
          d4h_team_id: whoami.d4h_team_id,
          d4h_api_host: view_model.api_host,
          mailing_address: "",
          lat: lat,
          lng: lng,
          timezone: d4h_team.timezone,
          d4h_access_key: view_model.access_key,
          d4h_access_key_saved_at: DateTime.utc_now(),
          d4h_access_key_owner: D4H.WhoAmI.member_name(whoami, whoami.d4h_team_id),
          d4h_access_key_member_id: D4H.WhoAmI.member_id(whoami, whoami.d4h_team_id)
        })

      Member.insert!(%{
        team_id: team.id,
        d4h_member_id: signer.d4h_member_id,
        ref_id: signer.ref_id,
        name: signer.name,
        email: signer.email,
        phone: signer.phone,
        address: signer.address,
        position: signer.position,
        joined_at: signer.joined_at,
        left_at: signer.left_at,
        d4h_permission: signer.permission,
        d4h_status: signer.status
      })

      team
    end)
    |> elem(1)
  end

  defp form_error(params, field, message) do
    params
    |> TeamSignupViewModel.build_new_changeset()
    |> add_error(field, message)
    |> Map.put(:action, :insert)
  end
end
