defmodule App.Operation.ChangeOwnPhone do
  @moduledoc """
  A member changes their own mobile number (#156). Text login uses it, so the new one
  must prove it works first: request/4 texts it a code, and confirm/4 takes the code
  back. Only then does the change go to D4H, as a change set of source `:member`, and
  the member's email gets a notice in case someone else made it. Members don't change
  their email; team admins do, in D4H.

  Numbers are E.164 (`+16045550123`), as a code's `sent_to`.
  """

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
  Checks the new number and texts it a code. `{:ok, e164}`, or `{:error, text}` to
  show. `allowed?`, given the number, is the caller's rate limit: false sends nothing,
  though the answer is the same.
  """
  def request(%Member{} = member, %User{} = user, input, allowed? \\ fn _ -> true end) do
    with {:ok, e164} <- parse(input),
         :ok <- check(member, e164) do
      if allowed?.(e164), do: send_code(user, e164), else: {:ok, e164}
    end
  end

  @doc "The number the user's live code went to, or nil."
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

  @doc """
  Takes the code for `e164`. A match changes D4H and the copy: `{:ok, member}`.
  `{:error, :wrong_code}` for a wrong or expired code, which counts against it, or
  `{:error, text}` when D4H refused.
  """
  def confirm(%Member{} = member, %User{} = user, e164, code, now) do
    case match_code(user, e164, code) do
      :ok -> apply_change(member, user, e164, now)
      :error -> {:error, :wrong_code}
    end
  end

  @doc "Whether another current member has this number, so text login won't work."
  def shared?(%Member{} = member, e164, now) do
    e164
    |> Member.current_emails_with_phone(now)
    |> Enum.reject(&(&1 == String.downcase(member.email || "")))
    |> Enum.any?()
  end

  defp parse(input) do
    case Service.Phone.normalize(input) do
      nil -> {:error, "Enter a mobile number with its area code, like 604-555-1234."}
      e164 -> {:ok, e164}
    end
  end

  defp check(member, e164) do
    cond do
      not Accounts.text_login?() ->
        {:error, "SAR Duty cannot send texts right now. Ask a team admin to change it."}

      e164 == Service.Phone.normalize(member.phone) ->
        {:error, "That is your mobile number already."}

      true ->
        :ok
    end
  end

  defp send_code(user, e164) do
    cancel(user)
    {code, token} = UserToken.build_code(user, "confirm", e164)
    Repo.insert!(token)

    case UserNotifier.deliver_confirm_text(e164, code) do
      :ok -> {:ok, e164}
      _error -> {:error, "The code did not send. Check the number and try again."}
    end
  end

  defp match_code(user, e164, code) do
    code = String.replace(code || "", ~r/\s/, "")

    case user |> UserToken.live_code_query("confirm", e164) |> Repo.one() do
      %UserToken{} = token ->
        if user |> UserToken.hash_code(code) |> Plug.Crypto.secure_compare(token.token) do
          cancel(user)
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

  # D4H holds a mobile number as people type it, so it goes formatted.
  defp apply_change(member, user, e164, now) do
    phone = Service.Phone.format(e164)

    row = %ChangeSetRow{
      action: :update_member,
      member_id: member.id,
      d4h_record_id: member.d4h_member_id,
      old_value: %{"phone" => member.phone},
      new_value: %{"phone" => phone}
    }

    change_set =
      ChangeSet.propose!(
        %ChangeSet{team_id: member.team_id, source: :member, proposed_by_user_id: user.id},
        [row]
      )

    case ApplyChangeSet.call(member.team, change_set, user, now) do
      {:ok, [%ChangeSetRow{status: :applied}]} ->
        updated = member |> Ecto.Changeset.change(phone: phone) |> Repo.update!()

        if member.email not in [nil, ""],
          do: UserNotifier.deliver_phone_changed(member.email, member.team, phone)

        {:ok, updated}

      {:ok, [%ChangeSetRow{error: error}]} ->
        {:error, error}

      {:error, _reason} ->
        {:error, "#{D4H.service_name(member.team)} did not take the change. Try again."}
    end
  end
end
