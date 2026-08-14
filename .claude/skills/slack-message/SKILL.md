---
name: slack-message
description: >
  Compose and send Slack messages that read like a person wrote them, and never
  post to Slack without explicit permission. Use ANY time a Slack message needs
  to be written — if Slack is involved and words need to go out, this skill
  applies. This includes: sending to a channel or DM, replying to a thread,
  responding to someone who messaged, drafting for later, scheduling, or
  figuring out what to say. Example phrasings (not exhaustive): "tell the team
  on Slack", "ping Priya about the deploy", "post an update to #eng-releases",
  "reply in that thread", "draft a Slack message", "<person> responded /
  messaged / replied on Slack, what should we say", "how should I respond to
  <person>", "what do we say back", "they said X, what should we say", "send
  them a message". When in doubt, invoke it. Composing and showing a draft in
  the conversation is safe and happens without asking; putting anything into
  Slack — creating a Slack draft, sending, scheduling, or broadcasting — always
  waits for the user to choose it.
user_invocable: true
arguments:
  - name: target
    description: "Optional: what to say and where (e.g. 'tell #eng-releases the deploy finished', or a rough message to polish). If omitted, use the message currently in play."
    required: false
---

# Writing a Slack message

You're helping the user say something to other people, under the user's own name, in a medium
where a bad message is seen instantly and can't be recalled. Two things matter: the words read
like the user wrote them (not like an AI drafted them), and the user — not you — decides when the
message actually leaves their hands.

## The one rule: the draft stays in the conversation until the user picks what happens to it

The draft lives **in the conversation** — right here in the chat, written out as the exact text you'd
send. That's private, reversible, and the clearest way to show your work. Write it here first, every
time. Don't create a Slack draft and don't post anything until the user has told you which they want.

1. Compose the message. If you're replying, skim the surrounding thread or channel first so the tone
   fits and you're not repeating what's already been said.
2. Show the full draft in the conversation — the exact words, in a quote or code block so there's no
   ambiguity about what would go out — and name the destination (which channel or person).
3. Ask the user what to do with it, offering three choices (use `AskUserQuestion` when it's available,
   otherwise just ask in plain text):
   - **Send it** — post it now with `slack_send_message`.
   - **Create draft** — save it as a Slack draft with `slack_send_message_draft`. It lands in the
     user's own Slack "Drafts & sent"; nothing is posted.
   - **Feedback** — they want changes. Revise, show the new draft, and ask the same question again.
     Loop until they pick Send it or Create draft.
4. Do exactly what they chose — nothing more.

`slack_send_message` posts immediately; `slack_schedule_message` posts later but just as unstoppably.
Both put words in front of other people that can't be un-said, so they run only because the user picked
**Send it** (or explicitly asked you to schedule) — never on your own initiative. This holds even if
the environment would pop its own tool-approval dialog: the user is approving *the words*, not just
clicking through a permission prompt.

## Which tools to use

**Compose and deliver:**

| Tool | What it does | When to call it |
|------|--------------|-----------------|
| *(none — write it in the chat)* | Shows the draft in the conversation | Always, first — before any Slack tool |
| `slack_send_message_draft` | Saves a draft in the user's Slack (nothing is posted) | User picked **Create draft** |
| `slack_send_message` | Posts a message now (channel, DM, or thread reply) | User picked **Send it** |
| `slack_schedule_message` | Posts a message at a future time | User asked to schedule it |

If a Slack draft already exists (the user picked **Create draft** earlier and later decides to send),
pass its `draft_id` to `slack_send_message` so the draft is cleaned up when the real message sends. To
reply in a thread, set `thread_ts` to the parent message's timestamp; add `reply_broadcast: true` only
when the reply genuinely belongs in the main channel too.

**Find the destination (read-only, safe):**

- `slack_search_channels` — turn a channel name ("eng-releases") into the `channel_id` the send tools
  need.
- `slack_search_users` — turn a person's name or email into a `user_id`. Use that `user_id` as the
  `channel_id` to DM them. The current user's own ID works for a self-DM / note-to-self.

**Read context before replying (read-only, safe):**

- `slack_read_channel`, `slack_read_thread` — skim the surrounding conversation first so your message
  matches the thread's tone and doesn't repeat what's already been said. Cheap insurance against a
  tone-deaf reply.

**Long content:** if the message is really a document (a spec, a long update), consider
`slack_create_canvas` / `slack_update_canvas` instead of a wall-of-text message. A canvas others can
see is outward-facing too — same rule, ask before you publish it.

## Team directory (skip the lookup for these people)

For anyone in this table, use their Slack ID directly as the `channel_id` — **don't** call
`slack_search_users` first. Only search for people who aren't listed here. First-name and common
nicknames resolve to the row (e.g. "ping Sumit", "tell Jiewen", "DM Pav" → Pavithran); if a first
name is genuinely ambiguous, ask which person.

This is the user's (kdickerson's) team — manager **Pradeep Dorairaj**'s org, Engineering-ML Platform
/ AIML — as of 2026-07-21. To refresh after a re-org or new hire, re-run `glean_employee_search`
with `reportsto:"Pradeep Dorairaj"` and read each person's Slack ID from their profile's SLACK link.

| Name | Slack ID | Role |
|------|----------|------|
| Kaleb Dickerson (you) | `U093HAAA338` | SWE, ML Platform |
| Pradeep Dorairaj (manager) | `U01F6HFTC1X` | Manager, SW Eng |
| Jiewen Huang | `U08P3R225CL` | Staff SWE, ML Platform |
| Gary Ren | `U045UA9UZC2` | Staff SWE, ML Platform / Data Sharing |
| Goutam Murlidhar | `U046TEAAMRR` | Staff SWE, SPCS / SnowVM / K8s |
| Sumit Sardana | `U073KR41JTF` | Sr SWE, AIML |
| Pavithran Ramachandran | `U06U7VAUQ2Z` | Sr SWE, AIML / ML Platform |
| Tyler Hoyt | `U04GX8YQYHG` | Sr SWE, AIML / ML Platform |
| Smitha Koduri | `U03PFQUK52A` | Sr SWE, Engineering |
| Chaoguang Lin | `WGYKPCVJT` | Sr SWE, ML Platform / FDB Core |
| Haoran Yu | `U02C5HPR4BD` | SWE, AIML / ML Platform / ML |
| Sasank Chindirala | `U08QN81PVPA` | SWE, ML Platform |
| Vivek Alamuri | `U08RXCAKGTY` | SWE, ML Platform |
| Sherry Li | `U09ANJVNKFZ` | SWE, AIML / ML Platform |
| Jack Douglas | `U09JUGAHS9K` | SWE, AIML |
| Huy Ngo | `U0AHSD3U7NF` | SWE, ML Platform |
| Satyam Goyal | `U0ASHRJ4HHB` | SWE Intern, ML Platform |

## Write like a person, not a bot

Slack is casual and fast. The AI tells that sink a cover letter sink a Slack message harder, because
everyone can feel them. Defaults:

- **Lead with the point.** The first line is often all anyone reads in a notification. Put the ask,
  the answer, or the news there — not a windup.
- **Cut the throat-clearing.** No "I hope this message finds you well", "Just wanted to reach out",
  "I wanted to take a moment to". Open with the substance.
- **Drop the AI vocabulary.** No *delve, leverage, robust, seamless, crucial, furthermore, moreover,
  additionally*. Plain words. "Use", not "leverage". "Important", not "crucial".
- **Ease off the em dash and the rule-of-three.** One "fast, reliable, and scalable" flourish and it
  reads as generated. A comma or a period usually does the job.
- **Match the room.** `#incidents` is terse and urgent; a team-social channel is loose. Read a couple
  of recent messages if you're unsure of the register.
- **Keep it short and commit.** 1–3 short paragraphs. Say what you mean without hedging. If it's
  getting long, that's a sign it wants to be a canvas or a doc.

For a longer announcement or anything where voice really matters, the `natural-writing` skill goes
deeper on stripping the AI fingerprint — the same principles apply here in miniature.

## Formatting (write standard markdown, not raw mrkdwn)

The `slack_natoma` tools take **standard markdown** and translate it to Slack's native mrkdwn for
you. So write normal markdown — `**bold**`, `[text](url)` — not Slack's raw syntax (`*bold*`,
`<url|text>`). If you hand-write mrkdwn you'll get literal characters in the posted message.

| Format | Syntax |
|--------|--------|
| Bold | `**text**` |
| Italic | `_text_` |
| Strikethrough | `~~text~~` |
| Inline code | `` `code` `` |
| Code block | ` ```code``` ` |
| Quote | `> text` |
| Link | `[text](url)` |
| Bulleted list | `- item` |
| Numbered list | `1. item` |

Code blocks accept a language tag for syntax highlighting (` ```python `). `slack_send_message` also
accepts markdown **tables** and **headers** (`#`, `##`) — for tables, don't escape the structural
`|`; only escape a literal `\|` inside a cell. But a Slack message is a minimalist surface, so keep
tables small and simple; anything header- or table-heavy reads better as a `slack_create_canvas`
document (and there's a 5000-character limit per message anyway). Bold the key info (names, dates,
deadlines, action items) so it survives a quick scan, put blank lines between distinct thoughts, and
use bullets for anything with 3+ items instead of a run-on sentence.

## Thread vs. channel

- Replying to a specific message → reply **in the thread** (`thread_ts`), keeps the channel clean.
- Starting a new topic, announcement, or a question for the whole group → post **in the channel**.
- Continuing an existing conversation → find the original message and reply to it; don't open a new
  thread for the same thing.

**DMs are different.** In a direct message, threads add friction without benefit — the whole DM is already a single conversation. Default to a plain new message (`thread_ts` omitted) unless the user explicitly says "reply in thread" or there's a genuine ambiguity about which message is being addressed (e.g. two separate topics open simultaneously).

## What good looks like

**Before (drafted like an AI):**
> Hi team! I hope you're all doing well. I just wanted to take a moment to reach out and let you know
> that I have successfully completed the deployment of the batch-inference service. Furthermore, all
> of the relevant tests are passing. Please don't hesitate to let me know if you have any questions!

**After:**
> Batch-inference is deployed and all tests are green. ✅
>
> Ping me if anything looks off.

The rewrite leads with the news, drops the "I hope / I just wanted to / Furthermore / please don't
hesitate" scaffolding, and trusts the reader to ask if they need more.
