# Snowhouse OAuth token for opencode's Snowflake-hosted Anthropic/OpenAI providers.
# Same token Claude Code reads via `sf ai claude token` (apiKeyHelper) and Codex injects
# as OPENAI_API_KEY -- one Snowhouse token, shared across gateways. ~10h TTL; open a new
# shell to refresh if opencode starts getting auth errors.
export SNOWHOUSE_OAUTH_TOKEN="$(sf ai claude token 2>/dev/null)"

# `oc` = opencode with plan mode on by default, plus --yolo (auto-approve all
# permissions not explicitly denied -- same thing as --auto/--dangerously-skip-permissions,
# just the literal flag name). Kept as a separate alias (not baked into `opencode` itself)
# since OPENCODE_EXPERIMENTAL_PLAN_MODE is still experimental and not something we're fully
# committed to yet -- `opencode` stays vanilla.
oc() {
  OPENCODE_EXPERIMENTAL_PLAN_MODE=1 command opencode --yolo "$@"
}
