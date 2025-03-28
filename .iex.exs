import Ecto.Query
# import Ecto.Query, only: [from: 2]

alias App.Accounts.User
alias App.Model.Activity
alias App.Model.Attendance
alias App.Model.Member
alias App.Model.Team
alias App.Repo

alias Ecto.Changeset

defmodule H do
  def reload do
    IEx.Helpers.recompile()
    :code_recompiled
  end

  def update(schema, changes) do
    schema
    |> Changeset.change(changes)
    |> Repo.update()
  end

  def count(query), do: query |> select(count()) |> Repo.one()
end

import H, only: [reload: 0]
