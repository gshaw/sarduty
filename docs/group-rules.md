# Group rules

A group's rules say who belongs in it. The group page previews what they would change,
and a team admin reviews and applies them (#20).

## Rules

A group's rules are a list, and a member must meet every one (#334). Each rule is:

- **In any of**: the member is in at least one of its groups, or holds at least one of its
  endorsements.
- **Not in any of**: the member is in none of its groups and holds none of its
  endorsements.
- **Standing is any of**: the member's [standing](members.md#standing) today is one of
  Active, Away, or Not a person (#366).

No nesting. **A group's members** are whoever meets its rules when it has rules, and its
D4H members when it has none. So "In GSAR Qualified Callout" follows that group's rules,
never its D4H list, and no group depends on another being applied first. Someone kept in
a smart group by hand doesn't flow into the groups that use it: no standing exceptions.
**An endorsement's members** are whoever holds it. Rules never name a qualification.

```text
GSAR Qualified Callout   In: GSAR · In: PSLV Registration
MIT Callout              In: MIT 2026 · In: MIT Callout Approval
Callout                  In: GSAR Qualified Callout or MIT Callout · Standing is: Active
```

The Callout page reads "Members of GSAR Qualified Callout or MIT Callout who are active",
then a line for each group it names: what a smart group needs, or "Rope Rescue is a list
kept by hand."

**Standing is explicit** (#366, decided 2026-10-18). A group without a Standing rule takes
away members and bots like anyone else. When a group has rules but no Standing rule, the
editor suggests "Standing is Active" with a button; it is never added for the team. A
standing added to a group that has a Standing rule joins it, since two would need a
member to have both. Standing is worked out for today, so the preview proposes removing a
member the day their leave starts and adding them back the day after it ends. A team
admin still reviews and sends those changes; D4H never changes on its own. A team that
keeps an LOA group in D4H can go on using `Not in: LOA`.

This replaced two features: the endorsements a group's rule required (#320) and the group
a group started from (#327). A recurring requirement, such as 20 hours of rope practice a
year, is an expiring D4H qualification awarded each year (#15), and a group requires both
the course endorsement and the practice one.

## Groups kept by hand (#546)

A group has rules or is kept by hand, never both. Every team adds, renames, and deletes
groups in SAR Duty, and adds and removes the members of a group without rules, on the
group's page or the member's Groups tab. A group with rules changes only through Review
changes: a hand change would be undone by the next review, or by automatic mode (#419).
So its page says "Its rules decide who is in it." and has no add row or Remove buttons,
and [SetGroupMember](../lib/app/operation/set_group_member.ex) refuses it too.

- Each change is a change set of one row through
  [ApplyEdit](../lib/app/operation/apply_edit.ex), source `edit`. No sync follows it.
  [SaveTitledRecord](../lib/app/operation/save_titled_record.ex) and SetGroupMember write
  `groups` and `group_members` from the service's answer, as Review changes does, and the
  next 10-minute sync confirms it. A sync per click would fetch every group's members.
- A hand add or remove is logged to `group_membership_changes` with who made it and no
  reason, so Recent changes shows it beside the rules' changes.
- When other groups' rules name a hand-kept group, its page says so: an add there changes
  their pending changes.
- Two groups can't share a title, in any case, counting the organization's.
- Deleting a group deletes its own rules. Its confirm names what else stops: its members,
  the rules of groups that name it, the templates that add its members, and the attendance
  check.

**The organization's groups.** A team's list in D4H includes its organization's groups,
`owner.resourceType == "Organisation"`, kept as `groups.organization_owned`. Renaming or
deleting one might change it for every team in the organization, so SAR Duty never does,
on the page or in SaveTitledRecord. Adding and removing members is fine: the team's key
can, and the membership belongs to the team (checked live 2026-10-25). Their titles carry
the organization's short name, "Aircraft · BCSARA".

## Storage

- A [GroupRule](../lib/app/model/group_rule.ex) is `team_id`, `d4h_group_id` (the group it
  belongs to), and `kind`, `in`, `not_in`, or `standing`.
- A [GroupRuleReference](../lib/app/model/group_rule_reference.ex) is one group,
  endorsement, or standing in a rule. Exactly one of `endorsement_id`, a foreign key,
  `d4h_group_id`, and `standing` is set; a check constraint holds it.

A group is by D4H id, not a foreign key to `groups`. The sync deletes a group's row when
D4H drops it, and a foreign key would either take the rule with it or block the sync. A
missing group breaks the rule instead, so it plans nothing, and the page says "no longer
in D4H". Deleting an endorsement takes it out of every rule, and a rule left empty goes
too. The confirmation names the groups.

The migration made each endorsement in a group's rule `In: <endorsement>`, and each group
a group started from `In: <parent>`, first. A parent with no rule anywhere up its chain
added nothing before but would count its D4H list as an In rule, so it was dropped.

## Endorsements

An [Endorsement](../lib/app/model/endorsement.ex) is a team-level list that group rules
and ID cards share (#320).

- It is a name, unique within the team, and the qualifications that earn it
  ([EndorsementQualification](../lib/app/model/endorsement_qualification.ex), by
  `d4h_qualification_id`). Holding any one of them earns it.
- An [EndorsementInclude](../lib/app/model/endorsement_include.ex) makes one
  endorsement include another (#326): anything that earns the included one earns it too.
  7h First Aid lists OFA 1 and includes 40h First Aid, which includes 70h First Aid, so
  each course is listed once, at the lowest level it earns.

Includes point up the ladder, never "70h is 7h except…". A course added to 70h then
earns 7h too, which is right, and one added to 7h stays there. The other way, a new low
course would quietly earn every higher level. The loaders on `Endorsement` follow the
includes and fill `earned_by_ids`, so `Endorsement.qualification_ids/1` is the full list
and group rules, cards, and the endorsements page need nothing else. An include that
would make a loop is refused, and a loop already in the data stops instead of running
forever. Changing an endorsement's qualifications changes every group that uses it.

Considered and dropped: levels inside endorsements, "next level", creating endorsements
from a group's rules, rules that name qualifications, rules inside endorsements, and
automatic "or higher" wording.

## The endorsements page

`/teams/:subdomain/endorsements` lists each endorsement with what earns it, how many
current members hold it, and the group rules that use it. It flags, with a link to fix:
two endorsements with the same qualifications once includes are followed, a qualification
deleted in D4H, and one nothing earns. Each row lists its own qualifications, then
"or anything that earns" each one it includes. An endorsement's page adds and removes
includes and says which endorsements it counts toward. On a team with ID cards, a tick box per endorsement picks what cards list.

## Evaluation

[BuildGroupRulePreview](../lib/app/operation/build_group_rule_preview.ex):

- `load/2` reads the team once: every group's rules, groups and their D4H members,
  endorsements, qualification titles, awards, members, and each member's standing today.
  The groups list and the dashboard load it once for every group.
- `plan/3` is pure. An endorsement resolves to its holders (active awards), a smart group
  to whoever meets its rules, worked out recursively and memoized, and a group without
  rules to its D4H members. In rules intersect, Not in rules subtract, and only current
  members (`Member.current?/2`) are added. A retired member is removed for that
  alone.
- An award is active from `starts_at` until `ends_at`, either of which may be missing.
  `MemberQualificationAward.active?/2` is the one definition; the qualification and member
  pages use it too.

**Reasons.** Each removal carries the reason for each unmet rule, and `describe/3` turns
one into a sentence in the team's time zone:

- One endorsement: "No PSLV Registration on record", "PSLV Registration expired
  Oct 2, 2026", or when the next award starts.
- One smart group: that group's own unmet reasons. One hand-kept group: "Not in Rope
  Rescue".
- Several: "Not in GSAR Qualified Callout or MIT Callout", or "No First Aid 16 hours or
  MIT Callout Approval on record".
- Not in: "In LOA", or "Holds First Aid 16 hours".
- Standing: the standing, "Away until March 1, 2027 (Parental leave)" or "Not a person".

**Expiring** lists members who qualify now but won't within 60 days (D4H's default
reminder). It comes from endorsements, including those reached through smart groups. An
endorsement stays met until the latest end among its awards that haven't ended, so a
renewal already on record keeps a member off the list. An In rule lasts as long as the
last of its groups and endorsements, and a group as its first rule to run out. Hand-kept
lists and Not in rules don't expire.

The qualifications page's **Expiring** view is coarser on purpose (#367): every award
that ends within 30 to 180 days, 60 by default, with a Group filter on D4H's list. It
answers "who in Callout has something expiring?" without working out which awards a rule
needs. The home page's item counts the 60-day view, so its count and the list match.

**Safety.** `problems/2` lists why the rules can't plan, and any problem plans no
changes. The group page says why. Each would otherwise add every member or remove them
all, and a broken reference must stop the plan, not leave nobody out:

- No rules, or no In rule. Not in and Standing rules alone would add every member.
- A rule with no groups or endorsements left.
- An endorsement with no qualifications, or one naming a deleted qualification.
- A deleted group, or one whose own rules have a problem.
- A loop. The editor refuses one, and one already in the data stops.

## Applying the rules (#20)

The group page shows the rules as one sentence, with an **Edit rules** button that opens
the editor: the rules, and [In or Not in] [a group or endorsement] [Add rule]. A link
makes a new endorsement, which becomes an In rule. Each rule has its own page,
`/groups/:id/rules/:rule_id`, listing its groups and endorsements with Remove and a menu
to add another. Removing the last one removes the rule.

Adding the first rule to a group that other groups' rules name warns first: "Rope Rescue
Callout uses this group's list. Once it has rules, Rope Rescue Callout uses its rules
instead." Removing its last rule warns the other way.

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
