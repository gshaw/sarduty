defmodule App.Operation.SetInvitationReminders do
  @moduledoc """
  Turns a member's invitation reminders on or off (#444): from account settings, the page
  a reminder's link opens, or a mail app's one-click unsubscribe. SAR Duty's own setting;
  nothing goes to D4H.
  """
  alias App.Model.Member
  alias App.Repo

  def call(%Member{} = member, on?) when is_boolean(on?) do
    member |> Ecto.Changeset.change(invitation_reminders: on?) |> Repo.update!()
  end
end
