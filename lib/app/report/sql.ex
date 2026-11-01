defmodule App.Report.SQL do
  @moduledoc """
  SQL as `{iodata, params}`, joined so each `?` keeps its parameter in order.
  """

  @doc "Joins pieces, leaving out nil and false, with `separator` between them."
  def join(parts, separator \\ "") do
    {pieces, params} = parts |> Enum.filter(& &1) |> Enum.unzip()
    {Enum.intersperse(pieces, separator), Enum.concat(params)}
  end

  @doc "A piece named `name` in a select list."
  def as({sql, params}, name), do: {[sql, " AS ", name], params}

  @doc ~s(A table's name in a query: "s" for the subject, "p_member" for its parent member.)
  def table(nil), do: "\"s\""
  def table(parent), do: "\"p_#{parent}\""

  @doc "A column of a table."
  def column(table, column), do: [table, ".\"", Atom.to_string(column), "\""]

  @doc "A parameter as SQLite takes it: a time as the text it is stored as."
  def param(%DateTime{} = datetime),
    do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  def param(other), do: other
end
