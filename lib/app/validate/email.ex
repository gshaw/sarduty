defmodule App.Validate.Email do
  import Ecto.Changeset

  @max_length 50
  @email_regex ~r/\A\S+@\S+\.\S{2,}\z/

  # def valid_email?(email) do
  #   String.length(email) <= @max_length && email =~ @email_regex
  # end

  def call(changeset, field) do
    changeset
    |> validate_length(field, max: @max_length)
    |> validate_format(field, @email_regex, message: "must be a valid email address")
  end
end
