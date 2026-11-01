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
  - `args`: what a field takes in brackets, each `:days` (a whole number), `:period` (a
    filter's period: `'all'`, a year, or `'90d'`), `:tag` (a tag's title, or `'all'`), or
    `:group` (a group's title, or `'all'`). A period, a tag, or a group can be a picked
    value, as in `on_team(:when)` (#784); a picked group is its id.
  - `sql` builds a field from its args: `fn table, args, context -> {sql, params}`.
  - `query` is a rule's own query of the ids it keeps, `fn context, args -> query`: the
    field is `id IN (that query)`, true or false, so the rule stays in its home (#784).
  - `choices`: `fn context -> [{label, value}]`: what a `choice` field holds, or the
    titles a `list` field can include. A value picked for the field offers them.
  - `shown`: `fn context -> boolean`, whether the team, and the viewer, may read it, or
    nil for always. A field they may not read is no field to them, and an option, sort,
    or search that reads one drops out of the page (#784).
  - `hidden_choices`: `fn context -> [value]`, the values of a `choice` the viewer may
    not see, which `choices` leaves out for them. An option that compares with one drops
    out of the page, as Away does for members (#784).
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
    :query,
    :choices,
    :shown,
    :hidden_choices,
    args: [],
    hidden: false
  ]
end
