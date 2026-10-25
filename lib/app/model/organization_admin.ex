defmodule App.Model.OrganizationAdmin do
  use App, :model

  alias App.Accounts.User
  alias App.Field.TrimmedString
  alias App.Model.Event
  alias App.Model.Organization
  alias App.Model.OrganizationAdmin
  alias App.Repo
  alias App.Validate

  # An email a SAR Duty admin lets into an organization's space (#512). The email alone
  # logs them in, like a login grant: no D4H match. They see each team's totals, never
  # its people. Only SAR Duty admins add and remove them. Emails are stored lowercase.
  schema "organization_admins" do
    belongs_to :organization, Organization
    field :email, :string
    field :reason, TrimmedString
    belongs_to :added_by_user, User
    # Stamped at most hourly when they open an organization page. Never users.last_seen_at,
    # which would make their own team look recently used.
    field :last_seen_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  @seen_interval_seconds 60 * 60

  def build_changeset(data, params \\ %{}) do
    data
    |> cast(params, [:email, :reason])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:email], message: "Enter an email.")
    |> Validate.email(:email)
    |> validate_length(:reason, max: 200)
    |> validate_not_sar_duty_admin()
    |> unique_constraint([:organization_id, :email],
      error_key: :email,
      message: "This email is an organization admin already."
    )
  end

  # A row would let a SAR Duty admin log in without D4H (#141).
  defp validate_not_sar_duty_admin(changeset) do
    email = get_change(changeset, :email)

    if email && email in Enum.map(App.Accounts.admin_emails(), &String.downcase/1),
      do:
        add_error(
          changeset,
          :email,
          "Enter someone who is not a SAR Duty admin. SAR Duty admins already reach every organization."
        ),
      else: changeset
  end

  @doc "The organization's admins, by email, with who added each."
  def get_for_organization(%Organization{id: id}) do
    OrganizationAdmin
    |> where([a], a.organization_id == ^id)
    |> order_by([a], asc: a.email)
    |> preload(:added_by_user)
    |> Repo.all()
  end

  @doc "Every organization admin, grouped by organization id, for Admin › Organizations."
  def get_all_by_organization do
    OrganizationAdmin
    |> order_by([a], asc: a.email)
    |> Repo.all()
    |> Enum.group_by(& &1.organization_id)
  end

  @doc "The organizations this email is an admin of, by name."
  def organizations_for_email(email) when is_binary(email) do
    email = normalize(email)

    Organization
    |> join(:inner, [o], a in OrganizationAdmin, on: a.organization_id == o.id)
    |> where([o, a], a.email == ^email)
    |> order_by([o], asc: o.name)
    |> Repo.all()
  end

  def organizations_for_email(nil), do: []

  @doc "Whether the email is an admin of any organization, for logging in."
  def email_exists?(email) when is_binary(email) do
    email = normalize(email)
    OrganizationAdmin |> where([a], a.email == ^email) |> Repo.exists?()
  end

  @doc "Whether the user is one of this organization's admins. SAR Duty admins are not."
  def admin_of?(nil, _user), do: false

  def admin_of?(organization_id, %User{email: email}) when is_integer(organization_id) do
    email = normalize(email)

    OrganizationAdmin
    |> where([a], a.organization_id == ^organization_id and a.email == ^email)
    |> Repo.exists?()
  end

  @doc """
  Adds an organization admin, when a SAR Duty admin acts. `{:ok, admin}`, `{:error,
  changeset}` for a bad or repeated email, or `{:error, :forbidden}` for anyone else.
  """
  def add(%Organization{} = organization, params, %User{is_admin: true} = user) do
    changeset =
      build_changeset(
        %OrganizationAdmin{organization_id: organization.id, added_by_user_id: user.id},
        params
      )

    with {:ok, admin} <- Repo.insert(changeset) do
      Event.record!(:organization_admin_added,
        user_id: user.id,
        data: %{organization_id: organization.id, who: Event.who(admin.email)}
      )

      {:ok, admin}
    end
  end

  def add(%Organization{}, _params, %User{}), do: {:error, :forbidden}

  @doc "Removes one of the organization's admins, when a SAR Duty admin acts."
  def remove(%Organization{} = organization, id, %User{is_admin: true} = user) do
    case Repo.get_by(OrganizationAdmin, id: id, organization_id: organization.id) do
      nil ->
        {:error, :not_found}

      admin ->
        Repo.delete!(admin)

        Event.record!(:organization_admin_removed,
          user_id: user.id,
          data: %{organization_id: organization.id, who: Event.who(admin.email)}
        )

        {:ok, admin}
    end
  end

  def remove(%Organization{}, _id, %User{}), do: {:error, :forbidden}

  @doc """
  Stamps when this user last opened the organization's pages, at most hourly. Does
  nothing for someone who is not one of its admins, such as a SAR Duty admin.
  """
  def record_seen(organization_id, %User{} = user, now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -@seen_interval_seconds, :second)
    email = normalize(user.email)

    OrganizationAdmin
    |> where([a], a.organization_id == ^organization_id and a.email == ^email)
    |> where([a], is_nil(a.last_seen_at) or a.last_seen_at <= ^since)
    |> Repo.update_all(set: [last_seen_at: DateTime.truncate(now, :second)])

    :ok
  end

  defp normalize(email), do: email |> String.trim() |> String.downcase()
end
