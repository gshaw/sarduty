defmodule App.Operation.WithdrawDocument do
  @moduledoc """
  Ends a published PDF with no new one (#970), such as a claim published on the wrong
  incident. Its verify page then says who withdrew it and when, and shows nothing from
  it. It stays, and downloads for team admins, marked Withdrawn; nothing is deleted but
  with the team. Only a team admin of its team withdraws, and only a current one.
  """

  alias App.Accounts.User
  alias App.Model.PublishedPDF
  alias App.Model.Team
  alias App.Operation.PublishDocument

  @doc "`{:ok, pdf}` or `{:error, message}`."
  def call(%Team{} = team, %PublishedPDF{} = pdf, %User{} = user, now) do
    cond do
      pdf.team_id != team.id ->
        {:error, "This PDF is not your team's."}

      not PublishDocument.team_admin?(team, user, now) ->
        {:error, "Only a team admin can withdraw it."}

      PublishedPDF.status(pdf) != :current ->
        {:error, "It was replaced or withdrawn already. Reload to see it."}

      true ->
        withdraw(pdf, user, now)
    end
  end

  @doc """
  Withdraws each of `pdfs`, as Withdraw letters on the letters list does (#995):
  `%{withdrawn: [pdf], refused: [message]}`. One replaced or withdrawn meanwhile is
  refused alone.
  """
  def call_all(%Team{} = team, pdfs, %User{} = user, now) do
    results = Enum.map(pdfs, &call(team, &1, user, now))

    %{
      withdrawn: for({:ok, pdf} <- results, do: pdf),
      refused: for({:error, message} <- results, do: message)
    }
  end

  defp withdraw(pdf, user, now) do
    case PublishedPDF.withdraw(pdf, user, now) do
      {:ok, pdf} ->
        {:ok, pdf}

      {:error, :not_current} ->
        {:error, "It was replaced or withdrawn already. Reload to see it."}
    end
  end
end
