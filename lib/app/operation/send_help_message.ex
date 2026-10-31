defmodule App.Operation.SendHelpMessage do
  @moduledoc """
  Sends a Get help message (#780): one email to the team's contacts, the SAR Duty site
  admins, or both, as the sender ticked. A team with no contacts can't be ticked, and
  nothing ever falls back to every team admin. Inline, since the person waits to hear it
  went.
  """

  alias App.Mailer.HelpMailer
  alias App.Model.Member
  alias App.Model.Team
  alias App.ViewModel.HelpFormViewModel

  @doc """
  Pure. Who gets it, from the ticked values in `to`, the team's `contacts`, and the
  `site_admins` (App.Support.site_admins/1): `%{contacts:, site_admins:}`, each a list
  of `%{name:, email:}`, empty when not ticked.
  """
  def recipients(to, contacts, site_admins) do
    %{
      contacts: if("team" in to, do: contacts, else: []),
      site_admins: if("site_admins" in to, do: site_admins, else: [])
    }
  end

  @doc """
  Sends `params` (the form's `to` and `message`) from `sender`, `%{name:, email:}`, on
  `team`. `about` is `%{page:, device:}`. `{:ok, recipients}` as recipients/2 gives them,
  `{:error, changeset}` for the form, or `{:error, reason}` when the send fails.
  """
  def call(%Team{} = team, sender, params, about, now \\ DateTime.utc_now()) do
    contacts = Member.get_team_contacts(team, now)

    with {:ok, form} <- HelpFormViewModel.validate(%HelpFormViewModel{}, params, contacts != []),
         to = recipients(form.to, contacts, App.Support.site_admins(now)),
         :ok <- team |> HelpMailer.build(sender, form.message, to, about) |> HelpMailer.deliver() do
      {:ok, to}
    end
  end
end
