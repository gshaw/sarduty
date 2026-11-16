defmodule App.AI.Tool.CheckForm do
  @moduledoc """
  Checks a team's form's text as saving would (#1089), and saves nothing: every check
  App.Operation.SaveForm runs, through `SaveForm.check_for/5`, on the asker's team and
  the form's page. It reads no records. Its answer is the questions and places the text
  has, or the mistake.
  """
  @behaviour App.AI.Tool

  alias App.Operation.SaveForm

  @impl App.AI.Tool
  def name, do: "check_form"

  @impl App.AI.Tool
  def description do
    "Check a form's whole text as saving would, against this team's fields and the " <>
      "form's page, without saving it. Returns its questions and places, or the mistake. " <>
      "Check every text before you give it as your answer."
  end

  @impl App.AI.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{"text" => %{"type" => "string", "description" => "The form's text"}},
      "required" => ["text"]
    }
  end

  @impl App.AI.Tool
  def call(%{team: team, now: now, form: form, page: page}, %{"text" => text})
      when is_binary(text) and text != "" do
    case SaveForm.check_for(team, form, text, page, now) do
      {:ok, doc} ->
        {:ok,
         %{
           "ok" => true,
           "asks" => Enum.map(doc.asks, & &1.label),
           "places" => Enum.map(doc.places, &to_string(&1.name))
         }}

      {:error, _field, message} ->
        {:error, message}
    end
  end

  def call(_context, _args), do: {:error, "Give text as the form's whole text."}
end
