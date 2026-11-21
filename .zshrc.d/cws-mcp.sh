# Mac MCP for a cloud workspace without attaching tmux, for use with Rex.
# Reuses the helpers from cws-host.sh; `connect` stays the reference path.
[[ "$(uname -s)" == Darwin ]] || return

_cws_mcp_facade() {
  local id="$1" hash="$2" restart="${3:-0}"
  command sf ws ssh "$id" --command "
dir=\$HOME/.local/share/cws-host-mcp
if [ ! -f \"\$dir/tree.sha\" ] || [ \"\$(cat \"\$dir/tree.sha\")\" != \"$hash\" ]; then
  exit 42
fi
if [ \"$restart\" = 1 ]; then
  pid=\$(cat \"\$dir/facade.lock\" 2>/dev/null)
  if [ -n \"\$pid\" ]; then
    kill \"\$pid\" 2>/dev/null || true
    i=0
    while [ \"\$i\" -lt 50 ] && kill -0 \"\$pid\" 2>/dev/null; do
      sleep 0.1
      i=\$((i + 1))
    done
    kill -9 \"\$pid\" 2>/dev/null || true
  fi
fi
cd \"\$dir\" || exit 1
PYTHONPATH=. python3 facade.py --daemon --log \"\$dir/facade.log\" </dev/null >/dev/null 2>&1 || exit 1
PYTHONPATH=. python3 protocol.py upsert-mcp >/dev/null || exit 1
curl -fsS -m 3 http://127.0.0.1:18765/health >/dev/null || exit 1
"
}

cws-link() {
  "${HOME}/dotfiles/scripts/cws-link" "$@"
}

_cws_mcp_usage() {
  print -r -- "usage: cws-mcp up <workspace_id> | cws-mcp status [workspace_id] | cws-mcp down [workspace_id]" >&2
}

cws-mcp() {
  if ! (( $+functions[_cws_host_start_host] )); then
    print -r -- "cws-mcp: cws-host.sh helpers not loaded" >&2
    return 1
  fi
  local sub="$1" id hash st
  case "$sub" in
    up)
      id="$2"
      if [[ -z "$id" ]]; then
        _cws_mcp_usage
        return 1
      fi
      _cws_host_ensure_token || return 1
      _cws_host_persist_workspace "$id"
      hash="$(_cws_host_tree_hash)"
      _cws_host_start_host "$hash" || return 1
      _cws_host_start_tunnel "$id" || return 1
      _cws_mcp_facade "$id" "$hash" 0
      st=$?
      if [[ $st -eq 42 ]]; then
        print -r -- "cws-mcp: syncing tree to ${id}"
        _cws_host_upload "$id" || return 1
        _cws_mcp_facade "$id" "$hash" 1
        st=$?
      fi
      if [[ $st -ne 0 ]]; then
        print -r -- "cws-mcp: facade did not come up on ${id} (exit ${st})" >&2
        return $st
      fi
      print -r -- "cws-mcp: Mac MCP is up for ${id}; open the Rex host"
      ;;
    status|down)
      connect "$sub" "${2:-}"
      ;;
    *)
      _cws_mcp_usage
      return 1
      ;;
  esac
}
