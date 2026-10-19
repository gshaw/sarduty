defmodule App.Repo.Migrations.AddUtcZoneToOldTimes do
  use Ecto.Migration

  # Before ecto_sqlite3 0.17 (2024-10-25) UTC times were written with no zone, as
  # `2024-10-24T02:00:00`; since then they end in `Z`. SQLite compares them as text, so
  # the two shapes sorted apart at the same second. Every `utc_datetime` and
  # `utc_datetime_usec` column gets the `Z` that Ecto writes now. Only bare ISO 8601
  # values change; the time is the same, so down has nothing to undo.
  @columns [
    activities: ~w(deleted_at finished_at inserted_at started_at updated_at)a,
    attendance_links: ~w(closed_at inserted_at updated_at)a,
    attendance_scans: ~w(inserted_at override_at scanned_at updated_at)a,
    attendances: ~w(finished_at inserted_at started_at updated_at)a,
    change_set_rows: ~w(applied_at inserted_at updated_at)a,
    change_sets: ~w(applied_at discarded_at inserted_at updated_at)a,
    d4h_changes: ~w(seen_after seen_at)a,
    endorsement_includes: ~w(inserted_at updated_at)a,
    endorsement_qualifications: ~w(inserted_at updated_at)a,
    endorsements: ~w(inserted_at updated_at)a,
    equipment_items: ~w(expires_at inserted_at updated_at)a,
    equipment_usages: ~w(inserted_at updated_at)a,
    events: ~w(occurred_at)a,
    group_members: ~w(inserted_at updated_at)a,
    group_membership_changes: ~w(inserted_at)a,
    group_rule_references: ~w(inserted_at updated_at)a,
    group_rules: ~w(inserted_at updated_at)a,
    groups: ~w(inserted_at updated_at)a,
    mcp_calls: ~w(called_at)a,
    mcp_tokens: ~w(inserted_at last_used_at revoked_at)a,
    member_away_periods: ~w(inserted_at updated_at)a,
    member_cards:
      ~w(inserted_at pass_fetched_at pass_test_at pass_updated_at revoked_at updated_at)a,
    member_check_ins: ~w(inserted_at updated_at)a,
    member_qualification_awards: ~w(ends_at inserted_at starts_at updated_at)a,
    member_standing_changes: ~w(inserted_at)a,
    members: ~w(inserted_at joined_at left_at updated_at)a,
    no_shows: ~w(followed_up_at inserted_at updated_at)a,
    organizations: ~w(inserted_at updated_at)a,
    pass_registrations: ~w(inserted_at updated_at)a,
    qualifications: ~w(inserted_at updated_at)a,
    replaced_tax_credit_letters: ~w(certified_at inserted_at)a,
    short_links: ~w(expires_at inserted_at updated_at)a,
    tags: ~w(inserted_at updated_at)a,
    tax_credit_letters: ~w(inserted_at)a,
    team_login_grants: ~w(inserted_at updated_at)a,
    teams: ~w(d4h_access_key_saved_at d4h_refreshed_at d4h_synced_at inserted_at updated_at)a,
    template_groups: ~w(inserted_at updated_at)a,
    template_items: ~w(inserted_at updated_at)a,
    template_tags: ~w(inserted_at updated_at)a,
    templates: ~w(inserted_at updated_at)a,
    users: ~w(inserted_at last_seen_at updated_at)a
  ]

  @bare_seconds "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]"

  def up do
    for {table, columns} <- @columns, column <- columns do
      execute """
      UPDATE #{table} SET #{column} = #{column} || 'Z'
      WHERE #{column} GLOB '#{@bare_seconds}' OR #{column} GLOB '#{@bare_seconds}.[0-9]*[0-9]'
      """
    end
  end

  def down, do: :ok
end
