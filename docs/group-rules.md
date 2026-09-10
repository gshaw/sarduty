# Group rules

A group's rules say which qualifications a member must hold to belong to it. Today they
drive a preview on the group page; applying them to D4H is #20.

## Storage

Rules are in conjunctive normal form: `(A OR B) AND (C OR D)`.

- A [GroupRuleClause](../lib/app/model/group_rule_clause.ex) is one OR group, attached to
  a group by `d4h_group_id`.
- A [GroupRuleClauseQualification](../lib/app/model/group_rule_clause_qualification.ex)
  is one qualification in a clause, by `d4h_qualification_id`.

Both reference D4H ids rather than local foreign keys, so the rules survive a local row
being recreated by the sync.

## Evaluation

[BuildGroupRulePreview](../lib/app/operation/build_group_rule_preview.ex):

- `call/4` loads the team's awards for the qualifications the rules mention, runs
  `plan/4`, and loads the members to add and remove.
- `plan/4` is pure. A member qualifies when every clause lists at least one qualification
  they hold whose award has no `ends_at`, or one after `now`.
- **No clauses, or any empty clause, plans no changes.** An empty clause would otherwise
  disqualify everyone and empty the group. Keep this guard when rules start writing to D4H.

## Known gaps

These matter once the rules change D4H instead of only previewing:

- An award's `starts_at` is ignored, so an award dated in the future counts.
- Members who have left (`members.left_at`) can still qualify.
- A clause that names a qualification no local row has matches nobody, so every current
  member is planned for removal. The empty-clause guard doesn't catch this.
- Qualifications deleted in D4H are never deleted locally ([d4h-sync.md](d4h-sync.md)),
  so a rule can keep naming one.
- The clause events in [GroupLive](../lib/web/live/group_live.ex) change rows by the id
  the client sends, without checking that the clause belongs to the current team.

## Applying the rules (#20)

The plan in the issue is a manual mode first — pick groups, confirm the changes, and show
which clause removes each member — then an automatic batch mode. Both need a D4H write for
group membership, which the adapter doesn't have yet. `plan/4` is the part they share.
