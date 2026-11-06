defmodule App.Model.OutboxMessage do
  use App, :model

  import Ecto.Query

  alias App.Model.OutboxAttachment
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
    has_many :attachments, OutboxAttachment, preload_order: [asc: :position]
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
      attachments: OutboxAttachment.from_email(email)
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

  @doc "How many a team has after `since`, every one when nil: what's new since a visit."
  def count_since(%Team{} = team, nil), do: team |> scope() |> Repo.aggregate(:count)

  def count_since(%Team{} = team, since),
    do: team |> scope() |> where([m], m.inserted_at > ^since) |> Repo.aggregate(:count)

  @doc """
  The emails and texts a team has after message `after_id`, as `{emails, texts}`, and the
  newest id: what one burst brought.
  """
  def arrived_after(%Team{} = team, after_id) do
    counts =
      team
      |> scope()
      |> where([m], m.id > ^after_id)
      |> group_by([m], m.kind)
      |> select([m], {m.kind, count(m.id)})
      |> Repo.all()
      |> Map.new()

    {Map.get(counts, :email, 0), Map.get(counts, :text, 0)}
  end

  @doc "The id of a team's newest message, or 0."
  def last_id(%Team{} = team), do: team |> scope() |> Repo.aggregate(:max, :id) || 0

  @doc "Whether the message arrived after `since`; with nil, before any visit, all are."
  def new?(%OutboxMessage{}, nil), do: true
  def new?(%OutboxMessage{inserted_at: at}, since), do: DateTime.after?(at, since)

  @doc "One message, a team's or with `:all` any, or nil."
  def get(team_or_all, id),
    do: team_or_all |> scope() |> preload(attachments: ^attachment_heads()) |> Repo.get(id)

  @doc "One of a message's attachments, with its file, or nil."
  def get_attachment(%OutboxMessage{id: id}, attachment_id),
    do: Repo.get_by(OutboxAttachment, id: attachment_id, outbox_message_id: id)

  # A message's page lists its files, so it leaves their bytes out.
  defp attachment_heads do
    from(a in OutboxAttachment,
      order_by: a.position,
      select: %OutboxAttachment{
        id: a.id,
        outbox_message_id: a.outbox_message_id,
        position: a.position,
        filename: a.filename,
        content_type: a.content_type,
        size: fragment("length(?)", a.data)
      }
    )
  end

  @doc "Empties the outbox: a team's, or with `:all` every one."
  def delete_all(team_or_all) do
    {count, _rows} = team_or_all |> scope() |> Repo.delete_all()
    count
  end

  defp scope(:all), do: OutboxMessage
  defp scope(%Team{id: id}), do: where(OutboxMessage, team_id: ^id)
end
