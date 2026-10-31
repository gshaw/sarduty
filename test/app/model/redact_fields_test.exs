defmodule App.Model.RedactFieldsTest do
  @moduledoc """
  A field that can hold personal data or a secret is `redact: true`, so `inspect` hides
  it. Error messages print a function's arguments with `inspect`, and Honeybadger sends
  the message as it is, so a field without it reaches Honeybadger with any crash that
  touches its record. This fails when a schema field's name says it might hold one,
  unless it is listed below with what it holds. Ids and timestamps never hold one.
  """
  use ExUnit.Case, async: true

  @personal ~r/email|phone|address|contact|note|message|reason|text|description|content|value|token|code|key|secret|sent_to|signature|details/

  # Fields whose names match but hold no one's personal data or secret.
  @not_personal %{
    {App.Model.AttentionSnooze, :key} => "which Needs attention item, like retiring",
    {App.Model.Certificate, :content_type} => "a file's MIME type",
    {App.Model.ChoreCategory, :description} => "what a team's chore category is for",
    {App.Model.CustomField, :value_units} => "a D4H field's unit, like km",
    {App.Model.CustomField, :copy_values} => "a team setting",
    {App.Model.EquipmentItem, :barcode} => "the label on a piece of equipment",
    {App.Model.EquipmentItem, :custom_values} => "equipment's own fields",
    {App.Model.GroupMembershipChange, :reason} => "the group rule that made the change",
    {App.Model.LocationBookmark, :address} => "a team's saved place, like a hall",
    {App.Model.Team, :d4h_access_key_owner} => "the key owner's member name, like any name",
    {App.Model.Team, :mailing_address} => "the team's own address on its letters",
    {App.Model.TaxCreditLetter, :email_status} => "whether a letter's email was sent",
    {App.Model.Template, :custom_values} => "an activity template's defaults",
    {App.Accounts.UserToken, :context} => "the kind of token: session or login"
  }

  test "a field that might hold personal data or a secret is redacted" do
    {:ok, modules} = :application.get_key(:sarduty, :modules)

    exposed =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :__schema__, 1),
          module.__schema__(:source),
          field <- module.__schema__(:fields) ++ module.__schema__(:virtual_fields),
          name = Atom.to_string(field),
          Regex.match?(@personal, name),
          not String.ends_with?(name, ["_id", "_at"]),
          field not in module.__schema__(:redact_fields),
          not Map.has_key?(@not_personal, {module, field}),
          do: {module, field}

    assert exposed == [],
           "Give these `redact: true`, or list them in @not_personal with what they hold: " <>
             inspect(exposed)
  end
end
