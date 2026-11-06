defmodule App.Model.OutboxMessage do
  use App, :model

  import Ecto.Query

  alias App.Model.OutboxMessage
  alias App.Model.Team
  alias App.Repo

  # An email or text kept instead of sent (docs/outbox.md): a Try a demo team's always
  # (App.Mailer), and every one in dev (App.Adapter.Outbox, App.Adapter.Twilio). A team's
  # Outbox page shows its own; /dev/outbox shows all.
  schema "outbox_messages" do
    belongs_to :team, Team
    field :kind, Ecto.Enum, values: [:email, :text]
    field :from, :string
    field :to, :string
    field :subject, :string
    field :body, :string
    field :html_body, :string
    field :attachments, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @list_limit 200

  @doc "Keeps a Swoosh email for `team_id`, or for no team."
  def add_email!(%Swoosh.Email{} = email, team_id) do
    insert!(%OutboxMessage{
      team_id: team_id,
      kind: :email,
      from: email.from && address(email.from),
      to:
        email.to
        |> Enum.concat(email.cc)
        |> Enum.concat(email.bcc)
        |> Enum.map_join(", ", &address/1),
      subject: email.subject,
      body: email.text_body,
      html_body: email.html_body,
      attachments: attachment_names(email.attachments)
    })
  end

  @doc "Keeps a text to an E.164 number."
  def add_text!(to, body, team_id \\ nil),
    do: insert!(%OutboxMessage{team_id: team_id, kind: :text, to: to, body: body})

  # An open Outbox page shows a new message at once, so an agent waiting for an email
  # needn't reload.
  defp insert!(message) do
    message = Repo.insert!(message)
    event = {:outbox_message, message.team_id}
    Phoenix.PubSub.broadcast(App.PubSub, topic(), event)
    if message.team_id, do: Phoenix.PubSub.broadcast(App.PubSub, topic(message.team_id), event)
    message
  end

  @doc "The topic every new message is told on, as `{:outbox_message, team_id}`."
  def topic, do: "outbox"

  @doc "The topic one team's new messages are told on, as `{:outbox_message, team_id}`."
  def topic(team_id), do: "outbox:#{team_id}"

  defp address({"", email}), do: email
  defp address({nil, email}), do: email
  defp address({name, email}), do: "#{name} <#{email}>"

  defp attachment_names([]), do: nil
  defp attachment_names(attachments), do: Enum.map_join(attachments, ", ", & &1.filename)

  @doc "The newest first: a team's, or with `:all` every one."
  def list(team_or_all) do
    team_or_all
    |> scope()
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(@list_limit)
    |> Repo.all()
  end

  @doc "How many a team has."
  def count(%Team{} = team), do: team |> scope() |> Repo.aggregate(:count)

  @doc "One message, a team's or with `:all` any, or nil."
  def get(team_or_all, id), do: team_or_all |> scope() |> Repo.get(id)

  @doc "Empties the outbox: a team's, or with `:all` every one."
  def delete_all(team_or_all) do
    {count, _rows} = team_or_all |> scope() |> Repo.delete_all()
    count
  end

  defp scope(:all), do: OutboxMessage
  defp scope(%Team{id: id}), do: where(OutboxMessage, team_id: ^id)
end
