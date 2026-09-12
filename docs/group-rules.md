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
  `plan/4`, and returns the members to add, to remove, and expiring, each with a reason
  as text.
- `plan/4` is pure. A member qualifies when every clause lists at least one qualification
  they hold with an active award, and they haven't left the team (`Member.current?/2`).
- Each removal carries a reason per unmet clause: left the team, no award on record, the
  latest award expired, or the next award hasn't started. `describe/3` turns one into a
  sentence in the team's time zone.
- **Expiring** lists members who qualify now but won't within 60 days (D4H's default
  reminder). A clause stays met until the latest end among its awards that haven't ended,
  so a renewal already on record, even one that starts later, keeps a member off the list.
- An award is active from `starts_at` until `ends_at`, either of which may be missing.
  `MemberQualificationAward.active?/2` is the one definition; the qualification and member
  pages use it too.
- **No clauses, or any empty clause, plans no changes.** An empty clause would otherwise
  disqualify everyone and empty the group. Keep this guard when rules start writing to D4H.
- **A rule naming a qualification with no local row plans no changes.** That happens when
  the qualification is deleted in D4H, or deleted and recreated with a new id. The clause
  would match nobody and remove everyone. `call/4` checks
  `missing_qualification_ids/2` first, and the group page shows a warning until someone
  fixes the rule.

## Applying the rules (#20)

The group page shows the rules as one sentence, with an **Edit rules** button that opens
the clause editor.

**Review changes** on the group page opens
[GroupReviewLive](../lib/web/live/group_review_live.ex): every add and remove with its
reason, all ticked, and how old the data is, with a button to refresh from D4H.

[ApplyGroupRuleChanges](../lib/app/operation/apply_group_rule_changes.ex) does the work:

- It rebuilds the plan, so it only acts on members the plan lists, whatever ids the
  browser sends.
- It needs the team's own D4H key, and refuses while a rule is broken.
- Each change is `POST /member-group-memberships` or
  `DELETE /member-group-memberships/:id`, then the same change to `group_members`. A 404
  on delete counts as done. Neither is retried.
- Every change is logged to `group_membership_changes` with its reason, who clicked, and
  D4H's error if it failed. A failed change doesn't stop the rest. The group page shows
  the last ten.

The groups list shows which groups have rules, and how many changes are pending or that
a rule is broken. Automatic mode, stage 4 of #20, should go through the same operation.
