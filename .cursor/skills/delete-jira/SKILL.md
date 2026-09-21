---
name: delete-jira
description: >
  Request deletion of a Snowflake commercial Jira issue. Users cannot delete
  tickets; apply the admin-reviewed label instead. Use when the user asks to
  delete a Jira, remove a dummy/test ticket, drop a card that should not exist,
  or add the Jira deletion label. Not for closing real work as Won't Do /
  Cancelled / Done.
---

# Delete a Snowflake Jira

You cannot delete SNOW issues yourself. Jira admins do it after a review.

## Label

Add **exactly** this label, case-sensitive:

```
JIRA_ADMIN_DELETE_THIS_ISSUE
```

Official process: [Delete Test/Dummy Jira tickets?](https://snowflakecomputing.atlassian.net/wiki/spaces/ATA/pages/4491149349/Delete+Test+Dummy+Jira+tickets)

Admins review labeled issues about every two weeks, usually Friday. They move the ticket to a Trash project and archive it. Hard delete is on hold (security / legal); archive is what actually happens.

Do **not** use `delete_me`. People put that on tickets, but it is not the admin workflow.

## When to use this vs close the ticket

Use the delete label when the ticket should not exist: dummy, test, created in error, or a card that was filed and then dropped before it meant anything.

If the work was real and you are just not doing it, **transition** to Cancelled / Won't Do and leave it. Do not label those for deletion.

## How to apply it

1. Fetch the issue (`getJiraIssue`). Confirm it is a trash candidate, not a live piece of work.
2. `editJiraIssue` with **the full labels list**. The API replaces labels; if you send only the delete label you wipe the rest. Keep existing labels and append `JIRA_ADMIN_DELETE_THIS_ISSUE`.
3. Add a short comment saying why it should be deleted. Admins do a quick check that it really is a dummy/error ticket; the comment is that check.

Snowflake commercial cloudId: `6020aaef-9082-4a4e-a21a-d47b98ba3ddc`.

Atlassian MCP (`natoma_atlassian_remote`):

```
editJiraIssue
  cloudId: 6020aaef-9082-4a4e-a21a-d47b98ba3ddc
  issueIdOrKey: SNOW-XXXXXXX
  fields.labels: [<existing labels...>, "JIRA_ADMIN_DELETE_THIS_ISSUE"]

addCommentToJiraIssue
  cloudId: 6020aaef-9082-4a4e-a21a-d47b98ba3ddc
  issueIdOrKey: SNOW-XXXXXXX
  commentBody: why this ticket should not exist
  contentFormat: markdown
```

The issue stays visible until the Friday review. That is expected.

## Do not

- Call a Jira delete API. You do not have permission; it will fail.
- Relabel with `delete_me` or similar informal names.
- Delete tickets you did not file, or tickets that have real discussion, unless the user is explicit that this one is a dummy.
