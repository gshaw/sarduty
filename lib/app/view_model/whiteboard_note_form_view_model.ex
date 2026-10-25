defmodule App.ViewModel.WhiteboardNoteFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.WhiteboardNote

  # Post a note and Change note (#515). Show until is the last day the note shows, on the
  # team's calendar; App.Operation.SaveWhiteboardNote turns it into D4H's archivedAt.
  @primary_key false
  embedded_schema do
    field :text, Field.TrimmedString
    field :url, Field.TrimmedString
    field :until, :date
    field :important, :boolean, default: false
  end

  @default_days 14

  @doc "A new note's form, showing for 14 days."
  def new(today), do: %__MODULE__{until: Date.add(today, @default_days)}

  @doc "Post again: an old note's text, link, and Important, with a new Show until."
  def again(%WhiteboardNote{} = note, today),
    do: %{new(today) | text: note.text, url: note.url, important: note.important}

  @doc "Change note: the note as it is. A note that never archives shows for 14 days."
  def from_note(%WhiteboardNote{} = note, timezone, today) do
    %__MODULE__{
      text: note.text,
      url: note.url,
      important: note.important,
      until: WhiteboardNote.last_day(note, timezone) || Date.add(today, @default_days)
    }
  end

  @note_error "Enter a note of 3 to 140 characters"
  @link_error "Enter a full link, like https://example.com/agm"

  def changeset(form, params, today) do
    form
    |> cast(params, [:text, :url, :until, :important])
    |> validate_required([:text], message: @note_error)
    |> validate_length(:text, min: 3, max: 140, message: @note_error)
    |> validate_length(:url, max: 2083, message: @link_error)
    |> validate_format(:url, ~r/\A(https?:\/\/[^\s\/]+\S*|mailto:\S+@\S+)\z/i,
      message: @link_error
    )
    |> validate_required([:until], message: "Select a day after today")
    |> validate_change(:until, fn :until, until ->
      if Date.after?(until, today), do: [], else: [until: "Select a day after today"]
    end)
  end

  @doc "The form's values, or `{:error, changeset}` with its errors to show."
  def validate(form, params, today) do
    form |> changeset(params, today) |> apply_action(:validate)
  end
end
