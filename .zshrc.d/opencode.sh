# Snowhouse OAuth token for opencode's Snowflake-hosted Anthropic/OpenAI providers.
# Same token Claude Code reads via `sf ai claude token` (apiKeyHelper) and Codex injects
# as OPENAI_API_KEY -- one Snowhouse token, shared across gateways. ~10h TTL; open a new
# shell to refresh if opencode starts getting auth errors.
#
# Do not call `sf ai claude token` on every pane (~370ms). Reuse a cache file and
# refresh in the background when it is older than 8 hours.
() {
  setopt localoptions extendedglob
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/snowhouse-oauth-token"
  local token
  mkdir -p "${cache:h}"
  if [[ -r $cache ]]; then
    export SNOWHOUSE_OAUTH_TOKEN="$(<$cache)"
    [[ -z $cache(#qNmh+8) ]] && return
    (
      umask 077
      token=$(command sf ai claude token 2>/dev/null) || exit 0
      [[ -n $token ]] || exit 0
      print -r -- "$token" >"${cache}.tmp" && mv "${cache}.tmp" "$cache"
    ) >/dev/null 2>&1 &!
    return
  fi
  token=$(command sf ai claude token 2>/dev/null) || true
  [[ -n $token ]] || return
  umask 077
  print -r -- "$token" >"$cache"
  export SNOWHOUSE_OAUTH_TOKEN="$token"
}

# `oc` = opencode with plan mode on by default, plus --yolo (auto-approve all
# permissions not explicitly denied -- same thing as --auto/--dangerously-skip-permissions,
# just the literal flag name). Kept as a separate alias (not baked into `opencode` itself)
# since OPENCODE_EXPERIMENTAL_PLAN_MODE is still experimental and not something we're fully
# committed to yet -- `opencode` stays vanilla.
oc() {
  OPENCODE_EXPERIMENTAL_PLAN_MODE=1 command opencode --yolo "$@"
}
