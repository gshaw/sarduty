defmodule App.Report.Field do
  @moduledoc """
  A field a report can read, from App.Report.Catalog.

  - `type`: `:text`, `:number`, `:hours` (minutes, shown as hours), `:km`, `:date` (a
    UTC time shown as the team's date), `:bool`, `:list` (titles), `:choice` (one of
    `choices`), or `{:record, kind}` for a record the cell links to: `:member`,
    `:activity`, `:item`, `:qualification`, or `:group`.
  - `column`: its column in the subject's rows. A record field's `column` is the text it
    sorts and compares by, and `id_column` the record's id.
  - `parent`: for a field that names a parent record, such as attendance's `member`, the
    parent's name in the subject.
  - `args`: what a roll-up field takes, such as `not_seen(365)`'s days, and `sql` builds
    it: `fn table, args, context -> {sql, params}`.
  - `choices`: `fn context -> [{label, value}]`: what a `choice` field holds, or the
    titles a `list` field can include. A value picked for the field offers them.
  """

  @enforce_keys [:name, :label, :type]
  defstruct [
    :name,
    :label,
    :type,
    :about,
    :column,
    :id_column,
    :parent,
    :sql,
    :choices,
    args: [],
    hidden: false
  ]
end
