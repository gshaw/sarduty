defmodule App.ViewModel.LocationBookmarkFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.LocationBookmark

  # A saved place on a SAR Duty Records team (#614): its name, its address as one line,
  # and its pin, pasted as text a person would copy from a map.
  @primary_key false
  embedded_schema do
    field :title, Field.TrimmedString
    field :place, Field.TrimmedString
    field :pin, Field.TrimmedString
  end

  def from_bookmark(nil), do: %__MODULE__{}

  def from_bookmark(%LocationBookmark{} = bookmark) do
    pin = bookmark |> Activity.pin() |> Coordinate.build()

    %__MODULE__{
      title: bookmark.title,
      place: bookmark.address,
      pin: pin && Coordinate.to_string(pin, 5)
    }
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [:title, :place, :pin])
    |> validate_required([:title], message: "Enter a name.")
    |> validate_length(:title, max: 100)
    |> validate_length(:place, max: 100)
    |> validate_pin()
  end

  defp validate_pin(changeset) do
    pin = get_field(changeset, :pin)

    if pin == nil or Coordinate.parse(pin),
      do: changeset,
      else:
        add_error(changeset, :pin, "Enter a latitude and longitude, like 49.10788, -122.82894.")
  end

  @doc "The row's fields as a change set stores them: the pin as \"lat,lng\" or nil."
  def value(%__MODULE__{} = form) do
    pin = Coordinate.parse(form.pin)

    %{
      "title" => form.title,
      "place" => form.place || "",
      "location" => pin && Coordinate.to_string(pin, 5)
    }
  end
end
