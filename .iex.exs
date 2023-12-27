import Ecto.Query
# import Ecto.Query, only: [from: 2]

alias App.Model.Activity
alias App.Model.Attendance
alias App.Model.Member
alias App.Model.Team
alias App.Model.User
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
end

import H, only: [reload: 0]
