defmodule App.Mailer.HelpMailer do
  @moduledoc """
  Get help's one email (#780): from SAR Duty to everyone ticked, the team's contacts and
  the SAR Duty site admins on the To line, the sender on Cc for their copy, and Reply-To
  set to the sender, so Reply all keeps everyone on one thread. The footer says who sent
  it, from which page, who else got it, and the device. Sent inline: the member waits to
  hear it went.
  """
  import Swoosh.Email

  alias App.Mailer
  alias App.Model.Team

  @site_admins "SAR Duty site admins"

  @doc """
  Pure. The email for `message` from `sender` (`%{name:, email:}`, name may be nil) on
  `team`, to `to`, SendHelpMessage.recipients/3: the team's `contacts` and the
  `site_admins` ticked, each once. `about` has the `page` URL they came from and their `device`, either nil.
  """
  def build(%Team{} = team, sender, message, to, about) do
    from_name = sender.name || sender.email

    recipients =
      (to.contacts ++ to.site_admins)
      |> Enum.uniq_by(&String.downcase(&1.email))
      |> Enum.map(&{&1.name, &1.email})

    new()
    |> to(recipients)
    |> cc({sender.name || "", sender.email})
    |> from({"SAR Duty", "noreply@sarduty.com"})
    |> reply_to({sender.name || "", sender.email})
    |> subject("#{team.name}: a question from #{from_name}")
    |> text_body(text(team, from_name, message, to, about))
  end

  @doc "Sends the email build/5 makes. `:ok` or `{:error, reason}`."
  def deliver(%Swoosh.Email{} = email) do
    case Mailer.deliver(email) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc ~s(Pure. Who got it, for the footer and the banner: "Alex Chen, Sam Rivera, and the SAR Duty site admins".)
  def went_to(%{contacts: contacts, site_admins: site_admins}) do
    names =
      Enum.map(contacts, & &1.name) ++
        if(site_admins != [], do: ["the " <> @site_admins], else: [])

    Service.Format.and_list(names)
  end

  defp text(team, from_name, message, to, about) do
    footer =
      [
        "#{from_name}, on #{team.name}, sent this with Get help on SAR Duty." <>
          if(about.page, do: " They came from #{about.page}.", else: ""),
        "It went to #{went_to(to)}. Reply all to keep everyone on it.",
        about.device
      ]
      |> Enum.filter(& &1)
      |> Enum.join("\n")

    message <> "\n\n--\n" <> footer <> "\n"
  end
end
