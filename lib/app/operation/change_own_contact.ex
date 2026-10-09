defmodule App.Operation.ChangeOwnContact do
  @moduledoc """
  A member changes their own email or mobile number (#156). Both are how they log in,
  so the new one must prove it works first: request/4 sends a code to it, and confirm/5
  takes the code back. Only then does the change go to D4H, as a change set of source
  `:member`, and the old email gets a notice in case someone else made it.

  An email is a string; a mobile number is E.164 (`+16045550123`), as a code's `sent_to`.
  """

  import Ecto.Changeset

  alias App.Accounts
  alias App.Accounts.User
  alias App.Accounts.UserNotifier
  alias App.Accounts.UserToken
  alias App.Adapter.D4H
  alias App.Model.ChangeSet
  alias App.Model.ChangeSetRow
  alias App.Model.Member
  alias App.Operation.ApplyChangeSet
  alias App.Repo

  @doc """
  Checks the new email or number and sends it a code. `{:ok, sent_to}`, or
  `{:error, text}` to show. `kind` is `:email` or `:phone`. `allowed?`, given `sent_to`,
  is the caller's rate limit: false sends nothing, though the answer is the same.
  """
  def request(%Member{} = member, %User{} = user, kind, input, allowed? \\ fn _ -> true end)
      when kind in [:email, :phone] do
    with {:ok, sent_to} <- parse(kind, input),
         :ok <- check(member, kind, sent_to) do
      if allowed?.(sent_to), do: send_code(user, kind, sent_to), else: {:ok, sent_to}
    end
  end

  defp send_code(user, kind, sent_to) do
    user |> UserToken.by_user_and_contexts_query(["confirm"]) |> Repo.delete_all()
    {code, token} = UserToken.build_code(user, "confirm", sent_to)
    Repo.insert!(token)

    case deliver(kind, sent_to, code) do
      {:ok, _email} -> {:ok, sent_to}
      :ok -> {:ok, sent_to}
      _error -> {:error, "The code did not send. Check it and try again."}
    end
  end

  @doc "The email or number the user's live code went to, or nil."
  def pending(%User{} = user) do
    case user |> UserToken.live_code_any_query("confirm") |> Repo.one() do
      nil -> nil
      token -> token.sent_to
    end
  end

  @doc "Drops the user's waiting code, so the page offers a new one."
  def cancel(%User{} = user) do
    user |> UserToken.by_user_and_contexts_query(["confirm"]) |> Repo.delete_all()
    :ok
  end

  @doc "`:phone` for an E.164 number, else `:email`."
  def kind("+" <> _digits), do: :phone
  def kind(_email), do: :email

  @doc """
  Takes the code for `sent_to`. A match changes D4H and the copy and returns
  `{:ok, user}`: the user for the new email, whom the session moves to, or `user` for a
  new number. `{:error, :wrong_code}` for a wrong or expired code, which counts against
  it, or `{:error, text}` when D4H refused.
  """
  def confirm(%Member{} = member, %User{} = user, sent_to, code, now) do
    case match_code(user, sent_to, code) do
      :ok -> apply_change(member, user, kind(sent_to), sent_to, now)
      :error -> {:error, :wrong_code}
    end
  end

  @doc "Whether another current member of the team has this number, so text login won't work."
  def shared_phone?(%Member{} = member, e164, now) do
    e164
    |> Member.current_emails_with_phone(now)
    |> Enum.reject(&(&1 == String.downcase(member.email || "")))
    |> Enum.any?()
  end

  defp parse(:email, input) do
    changeset =
      {%{}, %{email: :string}}
      |> cast(%{email: String.trim(input || "")}, [:email])
      |> validate_required([:email], message: "Enter your new email.")
      |> App.Validate.email(:email)

    case apply_action(changeset, :insert) do
      {:ok, %{email: email}} -> {:ok, String.downcase(email)}
      {:error, changeset} -> {:error, changeset |> first_error()}
    end
  end

  defp parse(:phone, input) do
    case Service.Phone.normalize(input) do
      nil -> {:error, "Enter a mobile number with its area code, like 604-555-1234."}
      e164 -> {:ok, e164}
    end
  end

  defp first_error(changeset) do
    {_field, {message, _opts}} = hd(changeset.errors)
    message
  end

  defp check(member, :email, email) do
    cond do
      email == String.downcase(member.email || "") ->
        {:error, "That is your email already."}

      email_taken?(member, email) ->
        {:error, "Another member of your team has that email. Use your own."}

      true ->
        :ok
    end
  end

  defp check(member, :phone, e164) do
    cond do
      not Accounts.text_login?() ->
        {:error, "SAR Duty cannot send texts right now. Ask a team admin to change it."}

      e164 == Service.Phone.normalize(member.phone) ->
        {:error, "That is your mobile number already."}

      true ->
        :ok
    end
  end

  defp email_taken?(member, email) do
    import Ecto.Query

    Member
    |> where([m], m.team_id == ^member.team_id and m.id != ^member.id)
    |> where([m], fragment("lower(?)", m.email) == ^email)
    |> Member.current_query(DateTime.utc_now())
    |> Repo.exists?()
  end

  defp deliver(:email, email, code), do: UserNotifier.deliver_confirm_code(email, code)
  defp deliver(:phone, e164, code), do: UserNotifier.deliver_confirm_text(e164, code)

  defp match_code(user, sent_to, code) do
    code = String.replace(code || "", ~r/\s/, "")

    case user |> UserToken.live_code_query("confirm", sent_to) |> Repo.one() do
      %UserToken{} = token ->
        if user |> UserToken.hash_code(code) |> Plug.Crypto.secure_compare(token.token) do
          user |> UserToken.by_user_and_contexts_query(["confirm"]) |> Repo.delete_all()
          :ok
        else
          token
          |> Ecto.Changeset.change(failed_attempts: token.failed_attempts + 1)
          |> Repo.update!()

          :error
        end

      nil ->
        :error
    end
  end

  defp apply_change(member, user, kind, sent_to, now) do
    {field, key, value} = field(kind, sent_to)
    old = Map.fetch!(member, key)

    row = %ChangeSetRow{
      action: :update_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{field => old},
      new_value: %{field => value}
    }

    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: member.team_id, source: :member, proposed_by_user_id: user.id},
        [row]
      )

    case ApplyChangeSet.call(member.team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied}]} ->
        member |> change([{key, value}]) |> Repo.update!()
        notify(old_email(member), member, kind, value)
        {:ok, if(kind == :email, do: Accounts.get_or_create_user(value), else: user)}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, _reason} ->
        {:error, "#{D4H.service_name(member.team)} did not take the change. Try again."}
    end
  end

  # D4H holds a mobile number as people type it, so it goes formatted.
  defp field(:email, email), do: {"email", :email, email}
  defp field(:phone, e164), do: {"phone", :phone, Service.Phone.format(e164)}

  defp old_email(%Member{email: email}) when email not in [nil, ""], do: email
  defp old_email(_member), do: nil

  defp notify(nil, _member, _kind, _value), do: :ok

  defp notify(email, member, kind, value) do
    what = if kind == :email, do: "email", else: "mobile number"
    UserNotifier.deliver_contact_changed(email, member.team, what, value)
  end
end
