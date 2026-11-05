defmodule App.Model.TransferAward do
  use App, :model

  alias App.Model.Team
  alias App.Model.Transfer
  alias App.Model.TransferAwardFile

  # One award in a transfer (#892), as the sending team's D4H had it when the code was
  # made: its qualification, kept by title and D4H id so the receiving team can match it,
  # and its dates exactly as D4H keeps them. The certificate is a TransferAwardFile,
  # kept only while the code works; its name, type, and size stay.
  schema "transfer_awards" do
    belongs_to :team, Team
    belongs_to :transfer, Transfer
    has_one :file, TransferAwardFile
    field :position, :integer
    field :qualification_title, :string
    field :d4h_qualification_id, :integer
    # An organization's qualification is the same one on each of its teams (#652).
    field :organization_owned, :boolean, default: false
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :file_name, :string
    field :content_type, :string
    field :file_size, :integer
  end

  @doc "Whether the award had a certificate when the code was made."
  def certificate?(%__MODULE__{file_name: name}), do: not is_nil(name)
end
