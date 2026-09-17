---
name: teammates
description: >
  Directory of Kaleb Dickerson's immediate teammates with each person's Slack
  user ID, GitHub username, and email. Use whenever you need a teammate's
  identifier to act on their behalf — DMing, pinging, or tagging someone on
  Slack, requesting them as a PR reviewer (gh pr edit --add-reviewer <handle>),
  @-mentioning them in a PR or issue, or looking up their email / commit-author
  address. Fires on phrasings like "DM/ping/message <name>", "add <name> as a
  reviewer", "tag <name> on this PR", "what's <name>'s github / email / handle",
  or "who's on my team". Complements the slack-message skill (which only carries
  Slack IDs) by adding GitHub handles and emails.
---

# Teammates directory

Kaleb Dickerson's (self) immediate team — manager **Pradeep Dorairaj**'s org,
Engineering / ML Platform / AIML — as of 2026-07-21. Slack IDs and roles come
from the `slack-message` skill's roster; emails are from each person's Slack
profile and GitHub handles are verified against the `snowflake-eng/snowflake`
monorepo (login → real name confirmed via the GitHub users API).

| Name | Role | Slack ID | GitHub | Email |
|------|------|----------|--------|-------|
| Kaleb Dickerson (self) | SWE, ML Platform | `U093HAAA338` | `kaleb-dickerson_snow` | kaleb.dickerson@snowflake.com |
| Pradeep Dorairaj (manager) | Manager, SW Eng | `U01F6HFTC1X` | `pradeep-dorairaj_snow` | pradeep.dorairaj@snowflake.com |
| Jiewen Huang | Staff SWE, ML Platform | `U08P3R225CL` | `jiewen-huang_snow` | jiewen.huang@snowflake.com |
| Gary Ren | Staff SWE, ML Platform / Data Sharing | `U045UA9UZC2` | `gary-ren_snow` | gary.ren@snowflake.com |
| Goutam Murlidhar | Staff SWE, SPCS / SnowVM / K8s | `U046TEAAMRR` | `goutam-murlidhar_snow` | goutam.murlidhar@snowflake.com |
| Sumit Sardana | Sr SWE, AIML | `U073KR41JTF` | `sumit-sardana_snow` | sumit.sardana@snowflake.com |
| Pavithran Ramachandran | Sr SWE, AIML / ML Platform | `U06U7VAUQ2Z` | `p-ramachandran_snow` | p.ramachandran@snowflake.com |
| Tyler Hoyt | Sr SWE, AIML / ML Platform | `U04GX8YQYHG` | `tyler-hoyt_snow` | tyler.hoyt@snowflake.com |
| Smitha Koduri | Sr SWE, Engineering | `U03PFQUK52A` | `smitha-koduri_snow` | smitha.koduri@snowflake.com |
| Chaoguang Lin | Sr SWE, ML Platform / FDB Core | `WGYKPCVJT` | `chaoguang-lin_snow` | chaoguang.lin@snowflake.com |
| Haoran Yu | SWE, AIML / ML Platform / ML | `U02C5HPR4BD` | `haoran-yu_snow` | haoran.yu@snowflake.com |
| Sasank Chindirala | SWE, ML Platform | `U08QN81PVPA` | `sasank-chindirala_snow` | sasank.chindirala@snowflake.com |
| Vivek Alamuri | SWE, ML Platform | `U08RXCAKGTY` | `vivek-alamuri_snow` | vivek.alamuri@snowflake.com |
| Sherry Li | SWE, AIML / ML Platform | `U09ANJVNKFZ` | `sherry-li_snow` | sherry.li@snowflake.com |
| Jack Douglas | SWE, AIML | `U09JUGAHS9K` | `jack-douglas_snow` | jack.douglas@snowflake.com |
| Huy Ngo | SWE, ML Platform | `U0AHSD3U7NF` | `huy-ngo_snow` | huy.ngo@snowflake.com |
| Satyam Goyal | SWE Intern, ML Platform | `U0ASHRJ4HHB` | `satyam-goyal_snow` | satyam.goyal@snowflake.com |

## Usage

- **Slack ID** → pass directly as the `channel_id` for the `slack_natoma` tools
  to DM the person (or as `thread_ts`/channel context). Skip `slack_search_users`
  for anyone listed here.
- **GitHub** → request as a PR reviewer with
  `gh pr edit <pr> --add-reviewer <handle>` (the monorepo org is `snowflake-eng`),
  or `@<handle>` to mention them in a PR/issue comment.
- **Email** → direct contact, calendar invites, and commit-author lookups
  (e.g. `gh api "repos/snowflake-eng/snowflake/commits?author=<email>"`).

## Refresh

After a re-org or new hire, re-derive the roster from Glean employee search with
`reportsto:"Pradeep Dorairaj"`, then re-run the per-person lookups: Slack email
via `slack_read_user_profile`, and GitHub handle via the monorepo commits API
(`gh api "repos/snowflake-eng/snowflake/commits?author=<email>&per_page=1" --jq
'.[0].author.login'`), verifying each login's name with `gh api /users/<login>
--jq .name`. Handles follow the `<first>-<last>_snow` pattern.
