---
name: snowflake
description: Gather Snowflake platform context using Glean search and public docs. Use when you need internal Snowflake knowledge, codebase info, docs, or environment-specific answers.
user_invocable: true
arguments:
  - name: question
    description: "The question or topic to research"
    required: true
  - name: source
    description: "Where to search: 'glean', 'docs', or 'all' (default: all)"
    required: false
---

# Snowflake Skill

Gather context about Snowflake platform internals, codebase, documentation, environments, and architecture. Routes questions to the right source and keeps results out of the main context window.

## Sources

### 1. Glean (Internal Knowledge Search)

Use Glean for:
- Internal documentation, design docs, RFCs, tech specs
- Slack conversations and threads about Snowflake topics
- Code search across Snowflake repositories
- People and team information
- Jira tickets, Confluence pages, Google Docs
- Environment-specific knowledge captured in internal docs or tickets

### 2. Snowflake Public Docs (docs.snowflake.com)

Use public docs for:
- Official product documentation, SQL reference, and syntax
- Feature guides, tutorials, and best practices
- Release notes and known limitations
- Anything a customer would see in the public documentation

## Routing Logic

Determine the best source based on the question:

| Question Type | Source | Examples |
|---|---|---|
| Internal docs, design decisions, RFCs | Glean | "What's the design doc for feature X?", "Who owns service Y?" |
| Slack threads, discussions | Glean | "What did the team decide about Z?", "Any discussion on topic W?" |
| Internal code search | Glean | "Where is function X implemented?", "Find the PR for change Y" |
| Snowflake product docs, SQL help | Public Docs | "How do dynamic tables work?", "Syntax for CREATE STAGE" |
| Official feature reference, release notes | Public Docs | "What are the limits on external stages?", "CREATE STAGE syntax" |
| Architecture, platform internals | Both | "How does service X work and what's its Snowflake footprint?" |

If the `source` argument is provided, use that. Otherwise, default to all sources in parallel.

## Execution

**All searches MUST be done via subagents (Task tool)** to keep results out of the main context window. Only the synthesized answer should come back.

### Glean Subagent

Launch a Task with `subagent_type: "general-purpose"` that uses the Glean MCP tools:

- **`mcp__glean_default__search`** — keyword search for documents, code, messages
- **`mcp__glean_default__code_search`** — search internal code repositories
- **`mcp__glean_default__chat`** — AI-powered synthesis across multiple sources
- **`mcp__glean_default__employee_search`** — find people, teams, org info
- **`mcp__glean_default__read_document`** — read full document content from URLs found in search

Glean search tips:
- Use short, targeted keywords — not full sentences
- Use filters: `owner:"name"`, `from:"name"`, `updated:past_week`, `app:"github"`, `app:"slackentgrid"`, `app:"confluence"`
- For code: use `code_search` with function/class names, not natural language. Start in the two repos that cover most questions: `snowflake-eng/snowflake` (Global Services — SQL, planner, job execution) and `snowflake-eng/snowml` (ML client and container runtime). Widen only if the hit is clearly elsewhere.
- Chain: search first, then `read_document` on the most relevant URLs for full content
- For complex questions requiring synthesis: use `chat` tool

### Snowflake Public Docs Subagent

Launch a Task with `subagent_type: "general-purpose"` that fetches from docs.snowflake.com:

1. **WebSearch** to find the right doc page:
   ```
   WebSearch: "site:docs.snowflake.com <topic keywords>"
   ```
2. **WebFetch** to read the doc page content:
   ```
   WebFetch: url=<doc_url>, prompt="Extract the relevant information about <topic>"
   ```

Public docs tips:
- Always search with `site:docs.snowflake.com` to scope results to official docs
- Fetch the top 1-2 most relevant URLs — don't scrape the whole site
- The docs site is well-structured: SQL reference, guides, and API docs are separate sections
- If a page redirects, WebFetch will tell you — follow the redirect URL
- Cross-reference with Glean results when possible to catch internal-vs-public discrepancies

### Parallel Execution

When multiple sources are needed, launch subagents **in parallel** as separate Task calls in the same message. For example, a product docs question might launch both a Public Docs subagent and a Glean subagent simultaneously.

## Response

After subagents return:
1. Synthesize findings into a concise answer
2. Cite sources where relevant (doc URLs from Glean)
3. Flag any contradictions between sources
4. If neither source had a good answer, say so and suggest where the user might look

## Important

- **Always use subagents** — never call Glean MCP tools directly in the main conversation
- **Summarize, don't dump** — the whole point is to keep the main context clean
- **Respect permissions** — Glean results are permission-filtered; if nothing comes back, the doc may exist but be restricted
