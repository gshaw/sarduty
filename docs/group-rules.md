# Group rules

A group's rules say which qualifications a member must hold to belong to it. The group
page previews what they would change, and a team admin reviews and applies them (#20).

## Storage

Rules are in conjunctive normal form: `(A OR B) AND (C OR D)`. Each OR is an
**endorsement**, a team-level list that group rules and ID cards share (#320).

- An [Endorsement](../lib/app/model/endorsement.ex) is a name, unique within the team,
  and the qualifications that earn it. Holding any one of them earns it. The rule
  sentence and the "No … on record" reason use the name.
- An [EndorsementQualification](../lib/app/model/endorsement_qualification.ex) is one
  qualification in it, by `d4h_qualification_id`.
- An [EndorsementInclude](../lib/app/model/endorsement_include.ex) makes one
  endorsement include another (#326): anything that earns the included one earns it too.
  7h First Aid lists OFA 1 and includes 40h First Aid, which includes 70h First Aid, so
  each course is listed once, at the lowest level it earns.
- A [GroupEndorsement](../lib/app/model/group_endorsement.ex) puts an endorsement in a
  group's rule, by `d4h_group_id`. A member must hold every one.

Includes point up the ladder, never "70h is 7h except…". A course added to 70h then
earns 7h too, which is right, and one added to 7h stays there. The other way, a new low
course would quietly earn every higher level. The loaders on `Endorsement` follow the
includes and fill `earned_by_ids`, so `Endorsement.qualification_ids/1` is the full list
and group rules, cards, and the endorsements page need nothing else. An include that
would make a loop is refused, and a loop already in the data stops instead of running
forever.

Rules reference D4H ids rather than local foreign keys, so they survive a local row being
recreated by the sync. Changing an endorsement's qualifications changes every group that
uses it.

Before #320 each group kept its own clauses, and clauses with the same name were merged
only on cards. Copies drifted: South Fraser had three different "First Aid (7 hours or
higher)" lists. The migration ([PlanEndorsements](../lib/app/operation/plan_endorsements.ex))
kept every group's rule exactly: identical lists merged, and a name covering different
lists stayed on the longest. The old `group_rule_clauses` tables stay for one release.

## The endorsements page

`/teams/:subdomain/endorsements` lists each endorsement with what earns it, how many
current members hold it, and the group rules that use it. It flags, with a link to fix:
two endorsements with the same qualifications once includes are followed, a qualification
deleted in D4H, and one no member holds. Each row lists its own qualifications, then
"or anything that earns" each one it includes. An endorsement's page adds and removes
includes and says which endorsements it counts toward. On a team with ID cards, a tick box per endorsement picks what cards list.

## Evaluation

[BuildGroupRulePreview](../lib/app/operation/build_group_rule_preview.ex):

- `call/4` loads the team's awards for the qualifications the rules mention, runs
  `plan/4`, and returns the members to add, to remove, and expiring, each with a reason
  as text.
- `plan/4` is pure. A member qualifies when every endorsement in the rule lists at least one qualification
  they hold with an active award, and they haven't left the team (`Member.current?/2`).
- Each removal carries a reason per unmet endorsement: left the team, no award on record, the
  latest award expired, or the next award hasn't started. `describe/3` turns one into a
  sentence in the team's time zone.
- **Expiring** lists members who qualify now but won't within 60 days (D4H's default
  reminder). An endorsement stays met until the latest end among its awards that haven't ended,
  so a renewal already on record, even one that starts later, keeps a member off the list.
- An award is active from `starts_at` until `ends_at`, either of which may be missing.
  `MemberQualificationAward.active?/2` is the one definition; the qualification and member
  pages use it too.
- **No endorsements, or any with no qualifications, plans no changes.** An empty one would
  otherwise disqualify everyone and empty the group. Keep this guard when rules start
  writing to D4H.
- **A rule naming a qualification with no local row plans no changes.** That happens when
  the qualification is deleted in D4H, or deleted and recreated with a new id. The
  endorsement would match nobody and remove everyone. `call/4` checks
  `missing_qualification_ids/2` first, and the group page shows a warning until someone
  fixes the rule.

## Applying the rules (#20)

The group page shows the rules as one sentence, with an **Edit rules** button that opens
the rule editor: the endorsements the rule requires, a menu to add one, and a link to make
a new one, which joins the rule.

**Review changes** on the group page opens
[GroupReviewLive](../lib/web/live/group_review_live.ex): every add and remove with its
reason, all ticked, and how old the data is, with a button to refresh from D4H.

[ApplyGroupRuleChanges](../lib/app/operation/apply_group_rule_changes.ex) does the work:

- It rebuilds the plan, so it only acts on members the plan lists, whatever ids the
  browser sends.
- It needs the team's own D4H key, and refuses while a rule is broken.
- The changes go to D4H as one [change set](change-sets.md): `POST
/member-group-memberships` or `DELETE /member-group-memberships/:id`, then the same
  change to `group_members` for each row that applied. A 404 on delete counts as done.
  Neither is retried.
- Every change is logged to `group_membership_changes` with its reason, who clicked, and
  D4H's error if it failed. A failed change doesn't stop the rest. The group page shows
  the last ten.

The groups list shows which groups have rules, and how many changes are pending or that
a rule is broken. Automatic mode, stage 4 of #20, should go through the same operation.
