defmodule App.ViewModel.HelpFormViewModel do
  use App, :view_model

  # Get help's form (#780): who it goes to and the message. `to` holds "team" and
  # "site_admins"; the team only when it has contacts, so a message never falls back to
  # every team admin.
  @primary_key false
  embedded_schema do
    field :to, {:array, :string}, default: []
    field :message, :string
  end

  @max_length 2000

  @doc "A new form: the team ticked when it has contacts, else the SAR Duty site admins."
  def new(contacts?), do: %__MODULE__{to: if(contacts?, do: ["team"], else: ["site_admins"])}

  @doc "Who can be ticked: the team only when it has contacts."
  def choices(contacts?), do: if(contacts?, do: ["team", "site_admins"], else: ["site_admins"])

  def changeset(form, params, contacts?) do
    form
    |> cast(params, [:to, :message])
    |> update_change(:to, &Enum.filter(&1, fn value -> value in choices(contacts?) end))
    |> update_change(:message, &normalize/1)
    |> validate_to()
    |> validate_required([:message], message: "Enter a message")
    |> validate_length(:message,
      max: @max_length,
      message: "Enter a message of #{Service.Format.characters(@max_length)} or fewer"
    )
  end

  # On the field, not the change: nothing ticked is the default, so it's no change.
  defp validate_to(changeset) do
    if get_field(changeset, :to) == [],
      do: add_error(changeset, :to, "Select who to send it to"),
      else: changeset
  end

  @doc "The form's values, or `{:error, changeset}` with its errors to show."
  def validate(form, params, contacts?) do
    form |> changeset(params, contacts?) |> apply_action(:validate)
  end

  defp normalize(text), do: text |> String.replace("\r\n", "\n") |> String.trim()
end
