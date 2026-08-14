---
name: sourcegraph
description: Search across all Snowflake repositories using the Sourcegraph `src` CLI. Use for cross-repo code search, symbol lookup, file retrieval, and repo discovery.
user_invocable: true
arguments:
  - name: query
    description: "What to search for — a code pattern, symbol name, file path, or natural language description of what you're looking for"
    required: true
  - name: repo
    description: "Repository scope (substring match, e.g. 'snowml' or 'snowflake-eng/snowml'). Omit for cross-repo search."
    required: false
---

# Sourcegraph Skill

Cross-repo code search across all Snowflake repositories via the `src` CLI. Keeps search results out of the main context window by running everything through subagents.

## When to Use

- Finding code across repos you don't have cloned locally
- Symbol search (function/class/type definitions) across the org
- Discovering which repos contain references to a pattern
- Retrieving specific files from remote repos
- Finding commit history or diffs matching a pattern
- Discovering repo names when you don't know the exact path

## Environment

Auth is pre-configured via `SRC_ENDPOINT` and `SRC_ACCESS_TOKEN` env vars. No setup needed.

## Execution

**All searches MUST run in subagents** to keep results out of the main context window.

Launch a subagent with `subagent_type: "general-purpose"` and instruct it to use the `src` CLI based on the query type.

### Interpreting the User's Query

Translate the user's intent into the right `src` command:

| User Intent | Command Pattern |
|---|---|
| Find code matching a pattern | `src search 'pattern'` |
| Find a symbol definition | `src search 'pattern type:symbol'` |
| Find files by path | `src search 'pattern type:path'` |
| Search commit messages | `src search 'pattern type:commit'` |
| Search diffs for a change | `src search 'pattern type:diff'` |
| Retrieve a specific file | `src api` with GraphQL (see below) |
| List/find repositories | `src repos list -query='term'` |

### Search Command — The Primary Workhorse

```bash
src search '<query>' -stream -display <N>
```

**Always use `-stream -display N`** for plain-text output. This bounds the output to N results and avoids overwhelming the subagent. Use `-display 20` as default, increase for exhaustive searches.

#### Query Syntax Reference

**Repo scoping:**
- `repo:snowml` — substring match (matches any repo containing "snowml")
- `repo:^snowflake-eng/snowml$` — exact match
- `repo:snowflake-eng/snowml` — prefix-anchored (more precise than bare substring)
- `-repo:fork` — exclude repos matching pattern

**File scoping:**
- `file:\.py$` — files matching regex
- `file:batch_inference/` — files under a path
- `-file:test` — exclude test files
- `lang:python` — filter by language

**Search types:**
- (default) — literal or regex content search
- `type:symbol` — symbol definitions (functions, classes, types)
- `type:path` — file path search
- `type:diff` — search within diffs
- `type:commit` — search commit messages
- `type:repo` — search repo names

**Result control:**
- `count:100` — increase result limit (default is 30)
- `select:file` — return only file paths (no content)
- `select:content` — return only matching content
- `select:repo` — return only repo names

**Boolean and grouping:**
- `foo AND bar` — both must match
- `foo OR bar` — either matches
- `NOT foo` — exclude pattern
- Regex is supported: `func\s+\w+Actor`

#### Example Queries

```bash
# Find a class definition across all repos
src search 'type:symbol ModelActor lang:python' -stream -display 20

# Find all Python files referencing BatchInferenceJob
src search 'BatchInferenceJob lang:python' -stream -display 30

# Find files by path
src search 'type:path ray_inference_job.py' -stream -display 10

# Search within a specific repo
src search 'repo:snowflake-eng/snowml timed_phase' -stream -display 20

# Find repos containing a term
src search 'BatchInferenceJob select:repo' -stream -display 10

# Search commit messages
src search 'type:commit batch inference refactor repo:snowflake-eng/snowml' -stream -display 10

# Search diffs for when something was added/changed
src search 'type:diff ModelBackend repo:snowflake-eng/snowml' -stream -display 10

# Exclude test files
src search 'repo:snowflake-eng/snowml RemoteModelActor -file:test' -stream -display 20
```

### JSON Output (When Structured Parsing is Needed)

For programmatic use, add `-json`:

```bash
# Non-streaming JSON — single JSON object with Results array
src search '<query>' -json

# Streaming JSON — NDJSON lines, different schema, ends with {"done":true}
src search '<query>' -stream -json
```

**Gotcha:** Streaming and non-streaming JSON have completely different schemas. Non-streaming returns `{"Results": [...]}`. Streaming returns one NDJSON line per match with a `{"done":true}` sentinel.

Prefer `-stream -display N` (plain text) unless you specifically need to parse structured output.

### File Retrieval via GraphQL API

To fetch the full contents of a specific file:

```bash
src api -query '
  query($repo: String!, $path: String!) {
    repository(name: $repo) {
      defaultBranch {
        target {
          ... on GitObject {
            blob(path: $path) {
              content
            }
          }
        }
      }
    }
  }
' -vars '{"repo": "snowflake-eng/snowml", "path": "path/to/file.py"}'
```

Alternatively, find the file with search first, then read it locally if the repo is cloned.

### Repo Discovery

```bash
# List repos matching a term
src repos list -query='snowml'

# Find repos containing specific code
src search 'pattern select:repo' -stream -display 20
```

## Gotchas

1. **`repo:` is substring match** — `repo:snowml` matches `snowflake-eng/snowml`, `snowflake-eng/snowml-commons`, etc. Use `repo:^snowflake-eng/snowml$` for exact match.
2. **Always bound output** — use `-stream -display N` to prevent massive output from overwhelming the subagent.
3. **Streaming vs non-streaming JSON differ** — don't mix up the schemas. Prefer plain text unless parsing is required.
4. **Regex by default** — search patterns are regex. Escape special chars: `\.`, `\(`, `\[`, etc.
5. **Timeout** — set a reasonable bash timeout (30s+) for large searches. The Sourcegraph instance can be slow on broad queries.

## Subagent Instructions Template

When launching the subagent, include these instructions:

> You have access to the `src` CLI (Sourcegraph) for cross-repo code search. Auth is pre-configured.
> Use `src search '<query>' -stream -display <N>` for bounded plain-text results.
> Use `src repos list -query='<term>'` to find repository names.
> Use `src api -query '<graphql>' -vars '<json>'` for file retrieval.
>
> The user wants: {query}
> {if repo: Scope to repo: repo:{repo}}
>
> Run the appropriate search, then summarize the key findings concisely.
> Include: matching files, repos, relevant code snippets, and line numbers.
> If the first query returns too many or too few results, refine and retry.

## Response

After the subagent returns:
1. Summarize the findings concisely
2. Include repo names, file paths, and line numbers for key matches
3. If multiple repos matched, organize by repo
4. If nothing was found, suggest query refinements
