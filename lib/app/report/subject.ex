defmodule App.Report.Subject do
  @moduledoc """
  What a query names after `from`: its rows, as `source`, an Ecto query on one team's
  records that selects every column its fields read, and its `parents`, each a field of
  another subject: `%{"member" => {"members", :member_id}}`.
  """

  @enforce_keys [:name, :label, :source, :fields]
  defstruct [:name, :label, :one, :many, :source, :fields, parents: %{}]
end
