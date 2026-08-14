---
name: snowflake
description: Gather Snowflake platform context using Glean search and Cortex CLI. Use when you need internal Snowflake knowledge, codebase info, docs, or environment-specific answers.
user_invocable: true
arguments:
  - name: question
    description: "The question or topic to research"
    required: true
  - name: connection
    description: "Snowflake connection name for environment-specific queries (e.g., snowhouse, prod3, preprod8)"
    required: false
  - name: source
    description: "Where to search: 'glean', 'cortex', 'docs', or 'all' (default: all)"
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

### 2. Snowflake Public Docs (docs.snowflake.com)

Use public docs for:
- Official product documentation, SQL reference, and syntax
- Feature guides, tutorials, and best practices
- Release notes and known limitations
- Anything a customer would see in the public documentation

### 3. Cortex (Snowflake's AI Agent)

Use Cortex for:
- Snowflake product documentation and SQL syntax
- Environment-specific queries (warehouse state, table schemas, query history)
- Snowflake architecture and feature questions
- Running or validating SQL against Snowflake
- Anything that benefits from Snowflake-native tool access (search objects, semantic views, etc.)

## Routing Logic

Determine the best source based on the question:

| Question Type | Source | Examples |
|---|---|---|
| Internal docs, design decisions, RFCs | Glean | "What's the design doc for feature X?", "Who owns service Y?" |
| Slack threads, discussions | Glean | "What did the team decide about Z?", "Any discussion on topic W?" |
| Internal code search | Glean | "Where is function X implemented?", "Find the PR for change Y" |
| Snowflake product docs, SQL help | Public Docs or Cortex | "How do dynamic tables work?", "Syntax for CREATE STAGE" |
| Official feature reference, release notes | Public Docs | "What are the limits on external stages?", "CREATE STAGE syntax" |
| Environment-specific state | Cortex (with connection) | "What tables exist in schema X?", "Show warehouse usage" |
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
- For code: use `code_search` with function/class names, not natural language
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
- Cross-reference with Glean/Cortex results when possible to catch internal-vs-public discrepancies

### Cortex Subagent

Launch a Task with `subagent_type: "general-purpose"` that runs cortex in headless mode via Bash:

```bash
cortex -p "<question>" 2>&1
```

With a specific connection (for environment-specific queries):
```bash
cortex -c <connection> -p "<question>" 2>&1
```

Cortex tips:
- Use `-p` flag for headless/non-interactive mode — this is mandatory
- Use `-c <connection>` when the question is about a specific environment
- Available connections: `snowhouse` (default/internal), `prod3`, `preprod8`, `qa6`, `gcppreprod3`, `azpp4`
- Cortex has access to Snowflake SQL execution, object search, docs search, semantic views, and more
- Set a reasonable timeout (60s+) — cortex queries can take a moment
- Tell the subagent to summarize the key findings concisely

### Parallel Execution

When multiple sources are needed, launch subagents **in parallel** as separate Task calls in the same message. For example, a product docs question might launch both a Public Docs subagent and a Cortex subagent simultaneously.

## Response

After subagents return:
1. Synthesize findings into a concise answer
2. Cite sources where relevant (doc URLs from Glean, connection/environment from Cortex)
3. Flag any contradictions between sources
4. If neither source had a good answer, say so and suggest where the user might look

## Important

- **Always use subagents** — never call Glean MCP tools or cortex directly in the main conversation
- **Summarize, don't dump** — the whole point is to keep the main context clean
- **Respect permissions** — Glean results are permission-filtered; if nothing comes back, the doc may exist but be restricted
- **Connection matters** — environment-specific questions without a connection will use the default (snowhouse); ask the user if unclear which environment they mean
