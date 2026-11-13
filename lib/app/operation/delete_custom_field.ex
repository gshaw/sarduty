defmodule App.Operation.DeleteCustomField do
  @moduledoc """
  A team admin deletes one of the team's own custom fields (#1056 step 4), only when no
  record holds an answer to it: otherwise it is archived, which keeps every answer. The
  answers are counted from the copy (`CustomField.answer_count/1`). One change set row,
  source `:edit`, and the copy loses the field once it applies.
  """

  alias App.Accounts.User
  alias App.Model.ChangeSetRow
  alias App.Model.CustomField
  alias App.Model.Team
  alias App.Operation.ChangeCustomField
  alias App.Operation.CreateCustomField

  @doc "`:ok`, or `{:error, text}`."
  def call(%Team{} = team, %User{} = user, %CustomField{} = field, now) do
    with :ok <- ChangeCustomField.check(team, field),
         :ok <- check_answers(CustomField.answer_count(field)),
         {:ok, _rows} <- CreateCustomField.send_rows(team, user, [row(field)], now),
         do: :ok
  end

  @doc "Whether a field with `count` answers can be deleted, or the text to show."
  def check_answers(0), do: :ok

  def check_answers(count) when count > 0,
    do: {:error, "Archive this field instead. Records have answers to it."}

  @doc "The row that deletes `field`. It keeps what the field was, for history."
  def row(%CustomField{} = field) do
    %ChangeSetRow{
      action: :delete_custom_field,
      d4h_record_id: field.d4h_custom_field_id,
      old_value: %{
        "target" => field.target,
        "title" => field.title,
        "field_type" => field.field_type
      },
      new_value: %{}
    }
  end
end
