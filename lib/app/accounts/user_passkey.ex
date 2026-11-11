defmodule App.Accounts.UserPasskey do
  @moduledoc """
  A passkey a user added (#129): a second way to log in, beside codes. SAR Duty keeps the
  public key and the credential id the browser made; the private key stays on the
  person's device or in their password manager. A passkey proves who someone is, not
  what they reach: a login still needs the email to match a current member in D4H
  (App.Accounts.may_log_in?/2).
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias App.Accounts.User
  alias App.Accounts.UserPasskey
  alias App.Repo

  schema "user_passkeys" do
    belongs_to :user, User
    field :credential_id, :binary
    # The COSE public key, as :erlang.term_to_binary/1 wrote it. See cose_key/1.
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :aaguid, :string
    # Where the passkey is saved, from its AAGUID, such as "iCloud Keychain".
    field :name, :string
    # The device and browser that added it, such as "iPhone, Safari".
    field :added_with, :string
    field :last_used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Whether `user` may add a passkey. SAR Duty site admins try passkeys first (#129); every
  account gets them once they have. Anyone who has one can log in with it.
  """
  def allowed?(%User{is_admin: admin?}), do: admin?

  @doc "The user's passkeys, oldest first."
  def list_for(%User{id: user_id}) do
    UserPasskey
    |> where(user_id: ^user_id)
    |> order_by([p], asc: p.inserted_at, asc: p.id)
    |> Repo.all()
  end

  @doc "How many passkeys each user has, as a map from user id to count."
  def count_by_user do
    UserPasskey
    |> group_by([p], p.user_id)
    |> select([p], {p.user_id, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "The passkey with this credential id, with its user, or nil."
  def get_by_credential_id(credential_id) when is_binary(credential_id) do
    UserPasskey |> where(credential_id: ^credential_id) |> preload(:user) |> Repo.one()
  end

  @doc "The passkey with this id, only when it belongs to `user`, or nil."
  def get_for(%User{id: user_id}, id) do
    UserPasskey |> where(user_id: ^user_id, id: ^id) |> Repo.one()
  end

  def insert(%User{} = user, attrs) do
    %UserPasskey{user_id: user.id}
    |> change(Map.take(attrs, [:credential_id, :public_key, :sign_count, :aaguid]))
    |> change(name: attrs.name, added_with: attrs[:added_with])
    |> unique_constraint(:credential_id)
    |> Repo.insert()
  end

  @doc "Notes a login with the passkey: when, and the authenticator's new sign count."
  def used!(%UserPasskey{} = passkey, sign_count, now) do
    passkey
    |> change(sign_count: sign_count, last_used_at: DateTime.truncate(now, :second))
    |> Repo.update!()
  end

  @doc "The public key, as wax_ checks a signature with it."
  def cose_key(%UserPasskey{public_key: key}), do: :erlang.binary_to_term(key, [:safe])

  @doc """
  Where a passkey is saved, from the AAGUID its authenticator reports: the common
  password managers and platform keychains. "Passkey" for one this list doesn't know,
  such as an all-zero AAGUID.
  """
  def name_for(aaguid), do: Map.get(names(), aaguid, "Passkey")

  # From the community list at github.com/passkeydeveloper/passkey-authenticator-aaguids.
  # cspell:ignore Dashlane NordPass aaguids
  defp names do
    %{
      "fbfc3007-154e-4ecc-8c0b-6e020557d7bd" => "iCloud Keychain",
      "dd4ec289-e01d-41c9-bb89-70fa845d4bf2" => "iCloud Keychain",
      "ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4" => "Google Password Manager",
      "adce0002-35bc-c60a-648b-0b25f1f05503" => "Chrome on Mac",
      "771b48fd-d3d4-4f74-9232-fc157ab0507a" => "Edge on Mac",
      "08987058-cadc-4b81-b6e1-30de50dcbe96" => "Windows Hello",
      "9ddd1817-af5a-4672-a2b9-3e3dd95000a9" => "Windows Hello",
      "6028b017-b1d4-4c02-b4b3-afcdafc96bb2" => "Windows Hello",
      "bada5566-a7aa-401f-bd96-45619a55120d" => "1Password",
      "d548826e-79b4-db40-a3d8-11116f7e8349" => "Bitwarden",
      "531126d6-e717-415c-9320-3d9aa6981239" => "Dashlane",
      "53414d53-554e-4700-0000-000000000000" => "Samsung Pass",
      "50726f74-6f6e-5061-7373-50726f746f6e" => "Proton Pass",
      "b84e4048-15dc-4dd0-8640-f4f60813c8af" => "NordPass",
      "0ea242b4-43c4-4a1b-8b17-dd6d0b6baec6" => "Keeper"
    }
  end
end
