defmodule App.ViewModel.LocationBookmarkFormViewModel do
  use App, :view_model

  alias App.Field
  alias App.Model.Activity
  alias App.Model.Coordinate
  alias App.Model.LocationBookmark

  # A saved place on a SAR Duty Records team (#614): its name, and its address and pin as
  # an activity's form takes them.
  @primary_key false
  embedded_schema do
    field :title, Field.TrimmedString
    field :place, Field.TrimmedString
    # The pin, "lat,lng" as the sync stores it, or nil.
    field :coordinate, :string
  end

  def from_bookmark(nil), do: %__MODULE__{}

  def from_bookmark(%LocationBookmark{} = bookmark) do
    pin = bookmark |> Activity.pin() |> Coordinate.build()

    %__MODULE__{
      title: bookmark.title,
      place: bookmark.address,
      coordinate: pin && Coordinate.to_string(pin, 5)
    }
  end

  def changeset(%__MODULE__{} = form, params \\ %{}) do
    form
    |> cast(params, [:title, :place, :coordinate])
    |> validate_required([:title], message: "Enter a name.")
    |> validate_length(:title, max: 100)
    |> validate_length(:place, max: 100)
    |> put_coordinate()
  end

  # A pasted latitude and longitude is the pin. Otherwise the pin is the one picked, kept
  # in the stored form, or none.
  defp put_coordinate(changeset) do
    pasted = changeset |> get_field(:place) |> Coordinate.parse()
    pin = pasted || changeset |> get_field(:coordinate) |> Coordinate.build()
    put_change(changeset, :coordinate, pin && Coordinate.to_string(pin, 5))
  end

  @doc "The row's fields as a change set stores them: the pin as \"lat,lng\" or nil."
  def value(%__MODULE__{} = form),
    do: %{"title" => form.title, "place" => form.place || "", "location" => form.coordinate}
end
