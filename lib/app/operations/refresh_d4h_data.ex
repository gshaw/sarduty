defmodule App.Operation.RefreshD4HData do
  alias App.Adapter.D4H
  alias App.Operation.RefreshD4HData

  def call(current_user) do
    d4h = D4H.build_context(current_user)
    RefreshD4HData.Members.call(d4h, current_user.team_id)
    RefreshD4HData.Activities.call(d4h, current_user.team_id)
    RefreshD4HData.Attendances.call(d4h, current_user.team_id)
    :ok
  end
end
