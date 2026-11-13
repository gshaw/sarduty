# Files

Files go in the file store, never SQLite (#1067). Litestream copies the database whole
every few seconds, so a photo in a row slows every backup and every restore.
[App.Adapter.FileStore](../lib/app/adapter/file_store.ex) is the store: the only module
that knows where files are, and the only one that makes a key.

## Where

| Server     | Store                                                            |
| ---------- | ---------------------------------------------------------------- |
| Production | S3 bucket `sarduty-files` in Calgary (`ca-west-1`)               |
| Dev        | `db/files/`, or `sarduty-files-dev` when `FILES_BUCKET` is set   |
| Tests      | A scratch folder per run; `App.FileStoreOff` switches it for one |

The buckets, their IAM users, and the keys are in the private `sarduty-ops` repo
(`tofu/aws/files.tf`, `runbooks/files-keys.md`). Each server reads `FILES_BUCKET`,
`FILES_ACCESS_KEY_ID`, and `FILES_SECRET_ACCESS_KEY` (config/runtime.exs). Calls are
signed with Req's `aws_sigv4`; there's no AWS library.

## The key

```text
{owner}/{id}/{kind}/{token}/{variant}.{ext}
orgs/4/logo/logo.png
site/integration-test/k3f9a2b1c0d4e5f6/check.txt
```

- **owner** is `teams`, `orgs`, or `site`. `site` is SAR Duty's own and has no id.
  Owner first, so deleting a team or an organization is one prefix:
  `FileStore.delete_all(:teams, 12)`.
- **kind** is one of the kinds below, from the fixed list in `FileStore`.
- **token** is random (`FileStore.new_token/0`), and the row that owns the files keeps
  it. Keys never show names or D4H ids, and deleting the row deletes its folder. A kind
  with one file per owner, like a logo, has none.
- **variant** names each file of one thing: `original`, `show`, `tile`.

Only `FileStore.key/5` makes a key. A string that starts a key anywhere else fails
`App.Adapter.FileStoreKeysTest`.

## Kinds

| Kind               | Owner  | What                               | Lifecycle                         |
| ------------------ | ------ | ---------------------------------- | --------------------------------- |
| `logo`             | `orgs` | An organization's logo, `logo.png` | Kept; replaced by a new upload    |
| `integration-test` | `site` | Adminland's Files test             | `expires=2d`; the test deletes it |

Coming, each in its own PR: activity photos and videos, member photos waiting for a
check (`expires=14d`), certificates, letters, forms, equipment photos, imports and
exports (`expires=7d`). The layout a year out is in #1067.

Team logos are not here yet: they are files on the volume (`Team.logo_file/1`), written
by the D4H refresh.

## The buckets

Every bucket is the same: Block Public Access, no ACLs, SSE-S3, HTTPS only, and
versioning. A replaced or deleted file's old version is gone for good after 30 days,
which is the 30-day promise. Short-lived files are tagged, not put in a folder:
`expires=2d`, `7d`, or `14d` deletes the file that many days after it was put.
`FileStore.put/3` tags a file from its kind.

## Rules

- A file's bytes never go in a SQLite column. The row keeps the token, and a time such
  as `logo_at` when it needs to say there is one.
- Put the file first, then save the row. A store that refuses the file leaves the row
  as it was.
- A file people see goes through the app, never a public bucket URL.
- Deleting a team or an organization deletes its prefix.

## Adding a kind

1. A line in `FileStore`'s `@kinds`: its folder, owner, whether it has a token, and its
   `expires` tag or nil.
2. A row in the table above. The test checks it names the owner and the tag.
3. An operation that puts the file and saves its row, and deletes both together.

No bucket or IAM change: the IAM user may reach the whole bucket.
