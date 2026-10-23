defmodule App.Repo.Migrations.AddAwardCertificates do
  use Ecto.Migration

  # The D4H document attached to an award, its certificate (#314). Nil when it has none,
  # and until the first sync after this.
  def change do
    alter table(:member_qualification_awards) do
      add :d4h_document_id, :integer
    end
  end
end
