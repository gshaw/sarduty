defmodule App.Repo.Migrations.AddEmailProblemToMembers do
  use Ecto.Migration

  # Why email to the member does not arrive, when the mail service blocks their address
  # for good: no_such_address, spam_report, or blocked. Nil while it works.
  def change do
    alter table(:members) do
      add :email_problem, :string
    end
  end
end
