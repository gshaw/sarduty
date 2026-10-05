defmodule App.Model.ShortLink do
  use App, :model

  alias App.Field.EncryptedString
  alias App.Model.ShortLink
  alias App.Model.Team
  alias App.Repo

  # A short URL, /s/<code>, that redirects to a path in SAR Duty. Codes are 8 lowercase
  # characters, about 40 bits, so they look nothing like an ID card's XXXX-XXXX code. The
  # target can hold a secret token, so it is stored encrypted, and lookups go by code.
  schema "short_links" do
    belongs_to :team, Team
    field :code, :string
    field :target, EncryptedString, redact: true
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end

  # No 0/o, 1/l/i: someone may read the code aloud or type it from a screen.
  # cspell:ignore abcdefghjkmnpqrstuvwxyz -- the code alphabet, a to z less i, l, and o
  @alphabet ~c"23456789abcdefghjkmnpqrstuvwxyz"
  @code_length 8
  @attempts 5

  def code_format, do: ~r/\A[#{@alphabet}]{#{@code_length}}\z/

  def generate_code, do: generate_code([])

  defp generate_code(acc) when length(acc) == @code_length, do: to_string(acc)

  # Bytes at or over the last whole multiple of the alphabet are thrown away, so every
  # character is equally likely.
  defp generate_code(acc) do
    <<byte>> = :crypto.strong_rand_bytes(1)
    limit = div(256, length(@alphabet)) * length(@alphabet)

    if byte < limit,
      do: generate_code([Enum.at(@alphabet, rem(byte, length(@alphabet))) | acc]),
      else: generate_code(acc)
  end

  @doc """
  A new short link to `target`, a path such as "/attendance/abc". Options: `:team_id` and
  `:expires_at`. Tries a new code if one is taken.
  """
  def create!(target, opts \\ []) do
    unless String.starts_with?(target, "/") and not String.starts_with?(target, "//"),
      do: raise(ArgumentError, "a short link's target must be a path, got: #{inspect(target)}")

    link = %ShortLink{
      target: target,
      team_id: opts[:team_id],
      expires_at: opts[:expires_at] && DateTime.truncate(opts[:expires_at], :second)
    }

    insert_with_new_code!(link, @attempts)
  end

  defp insert_with_new_code!(_link, 0),
    do: raise("no free short link code after #{@attempts} tries")

  defp insert_with_new_code!(link, attempts) do
    changeset =
      link
      |> change(code: generate_code())
      |> unique_constraint(:code)

    case Repo.insert(changeset) do
      {:ok, inserted} -> inserted
      {:error, _changeset} -> insert_with_new_code!(link, attempts - 1)
    end
  end

  @doc "The link for `code` that has not expired, or nil."
  def find_by_code(code, now) when is_binary(code) do
    ShortLink
    |> where([s], s.code == ^code)
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> Repo.one()
  end

  def find_by_code(_code, _now), do: nil

  @doc "Deletes the links with these ids, if they belong to `team`."
  def delete_all!(%Team{} = team, ids) do
    ShortLink
    |> where([s], s.team_id == ^team.id and s.id in ^ids)
    |> Repo.delete_all()
  end
end
