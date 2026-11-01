defmodule App.Report.Subject do
  @moduledoc """
  What a query names after `from`: its rows, as `source`, a function of the context that
  gives an Ecto query on one team's records selecting every column its fields read, or an
  App.Report.Source when some columns need a join of their own; and its `parents`, each a
  field of another subject: `%{"member" => {"members", :member_id}}`.
  """

  @enforce_keys [:name, :label, :source, :fields]
  defstruct [:name, :label, :one, :many, :source, :fields, parents: %{}]
end
