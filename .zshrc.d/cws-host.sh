# CWS host MCP: Mac tools for agents on a cloud workspace.
# No-op on non-Darwin so a Linux/CWS checkout does not define `connect`.
[[ "$(uname -s)" == Darwin ]] || return

_cws_host_src() {
  local candidate
  candidate="${HOME}/dotfiles/mcps/cws-host"
  if [[ -d "$candidate" ]]; then
    print -r -- "$candidate"
    return 0
  fi
  candidate="${${(%):-%x}:A:h:h}/mcps/cws-host"
  if [[ -d "$candidate" ]]; then
    print -r -- "$candidate"
    return 0
  fi
  return 1
}

_cws_host_state() {
  print -r -- "${HOME}/.local/share/cws-host-mcp"
}

_cws_host_py() {
  PYTHONPATH="$(_cws_host_src)" python3 "$@"
}

_cws_host_ensure_token() {
  _cws_host_py -c 'from protocol import ensure_token; ensure_token()'
}

_cws_host_persist_workspace() {
  local state id
  state="$(_cws_host_state)"
  id="$1"
  mkdir -p "$state"
  print -r -- "$id" >"${state}/workspace"
}

_cws_host_last_workspace() {
  local f
  f="$(_cws_host_state)/workspace"
  [[ -f "$f" ]] || return 1
  cat "$f"
}

_cws_host_tree_hash() {
  _cws_host_py -c 'import sys; from protocol import tree_hash; print(tree_hash(sys.argv[1]))' "$(_cws_host_src)"
}

_cws_host_wait_pid_dead() {
  local pid="$1" i
  [[ -n "$pid" ]] || return 0
  for i in {1..50}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -9 "$pid" 2>/dev/null || true
  sleep 0.1
}

_cws_host_host_healthy() {
  local src
  src="$(_cws_host_src)" || return 1
  PYTHONPATH="$src" python3 -c 'from protocol import read_token, HOST_PORT
from urllib.request import Request, urlopen
req = Request("http://127.0.0.1:%s/health" % HOST_PORT, headers={"Authorization": "Bearer %s" % read_token()})
urlopen(req, timeout=0.4).read()' 2>/dev/null
}

_cws_host_start_host() {
  local src state i pid local_hash running
  src="$(_cws_host_src)" || return 1
  state="$(_cws_host_state)"
  mkdir -p "$state"
  _cws_host_ensure_token
  local_hash="$(_cws_host_tree_hash)"
  running="$(cat "${state}/host.sha" 2>/dev/null || true)"
  pid="$(cat "${state}/host.lock" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && [[ "$local_hash" == "$running" ]] && _cws_host_host_healthy; then
    return 0
  fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && [[ "$local_hash" != "$running" ]]; then
    print -r -- "cws-host: recycling host (tree changed)"
    kill "$pid" 2>/dev/null || true
    _cws_host_wait_pid_dead "$pid"
  fi
  PYTHONPATH="$src" python3 "${src}/host.py" --daemon --log "${state}/host.log" || return 1
  for i in {1..25}; do
    if _cws_host_host_healthy; then
      print -r -- "$local_hash" >"${state}/host.sha"
      return 0
    fi
    sleep 0.15
  done
  print -r -- "connect: host did not become healthy; see ${state}/host.log" >&2
  return 1
}

_cws_host_upload() {
  local id="$1" src state stage hash
  src="$(_cws_host_src)" || return 1
  state="$(_cws_host_state)"
  hash="$(_cws_host_tree_hash)"
  stage="$(mktemp -d)"
  cp "$src"/host.py "$src"/facade.py "$src"/protocol.py "$src"/tools.py "$src"/lock.py "$src"/lockrun.py "$stage/"
  cp "${state}/token" "$stage/token"
  print -r -- "$hash" >"${stage}/tree.sha"
  COPYFILE_DISABLE=1 tar -C "$stage" -cf - . \
    | command sf ws ssh "$id" --command 'mkdir -p ~/.local/share/cws-host-mcp && tar -C ~/.local/share/cws-host-mcp -xf - && chmod 600 ~/.local/share/cws-host-mcp/token' \
    || { rm -rf "$stage"; return 1; }
  rm -rf "$stage"
  print -r -- "cws-host: uploaded tree ${hash[1,12]}"
}

_cws_host_enter() {
  local id="$1" hash="$2" restart="${3:-0}"
  command sf ws ssh "$id" --options "-t" --command "
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
PYTHONPATH=. python3 facade.py --daemon --log \"\$dir/facade.log\" || exit 1
PYTHONPATH=. python3 protocol.py upsert-mcp >/dev/null || exit 1
curl -fsS http://127.0.0.1:18765/health >/dev/null || exit 1
tmux attach || tmux new-session
"
}

_cws_host_start_tunnel() {
  local id="$1" src state pid i ready
  src="$(_cws_host_src)" || return 1
  state="$(_cws_host_state)"
  ready="${state}/tunnel-${id}.ready"
  pid="$(cat "${state}/tunnel-${id}.lock" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && grep -q '^2 ' "$ready" 2>/dev/null; then
    return 0
  fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    print -r -- "cws-host: tunnel pid ${pid} is stale (no ready file); recycling"
    kill "$pid" 2>/dev/null || true
    _cws_host_wait_pid_dead "$pid"
  fi
  PYTHONPATH="$src" python3 "${src}/tunnel.py" --workspace "$id" --daemon --log "${state}/tunnel-${id}.log" || return 1
  for i in {1..80}; do
    pid="$(cat "${state}/tunnel-${id}.lock" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && grep -q '^2 ' "$ready" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  print -r -- "connect: tunnel for ${id} did not stay up; see ${state}/tunnel-${id}.log" >&2
  return 1
}

_cws_host_usage() {
  print -r -- "usage: connect <workspace_id> | connect status [workspace_id] | connect down [workspace_id]" >&2
  print -r -- "workspace_id is the id column from \`sf ws ls\`" >&2
}

connect() {
  if ! command -v sf >/dev/null 2>&1; then
    print -r -- "connect: sf not found" >&2
    return 1
  fi
  if ! _cws_host_src >/dev/null; then
    print -r -- "connect: cannot find ~/dotfiles/mcps/cws-host" >&2
    return 1
  fi

  local sub id hash st
  if [[ "$1" == "status" || "$1" == "down" ]]; then
    sub="$1"
    id="${2:-$(_cws_host_last_workspace 2>/dev/null)}"
    if [[ -z "$id" ]]; then
      print -r -- "connect: no workspace id (pass it or run connect <id> first)" >&2
      return 1
    fi
    if [[ "$sub" == "status" ]]; then
      _cws_host_status "$id"
      return
    fi
    _cws_host_down "$id"
    return
  fi

  if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    _cws_host_usage
    return 1
  fi
  if [[ "$1" == -* ]]; then
    _cws_host_usage
    return 1
  fi
  id="$1"

  _cws_host_ensure_token || return 1
  _cws_host_persist_workspace "$id"
  _cws_host_start_host || return 1
  _cws_host_start_tunnel "$id" || return 1
  hash="$(_cws_host_tree_hash)"
  _cws_host_enter "$id" "$hash" 0
  st=$?
  if [[ $st -eq 42 ]]; then
    print -r -- "cws-host: syncing tree to ${id}"
    _cws_host_upload "$id" || return 1
    _cws_host_enter "$id" "$hash" 1
    return
  fi
  return $st
}

_cws_host_status() {
  local id="$1" state src host_pid tun_pid
  state="$(_cws_host_state)"
  src="$(_cws_host_src)"
  host_pid="$(cat "${state}/host.lock" 2>/dev/null || true)"
  tun_pid="$(cat "${state}/tunnel-${id}.lock" 2>/dev/null || true)"
  print -r -- "workspace: ${id}"
  print -r -- "host.lock pid: ${host_pid:-none}"
  print -r -- "tunnel.lock pid: ${tun_pid:-none}"
  if [[ -n "$host_pid" ]] && kill -0 "$host_pid" 2>/dev/null; then
    print -r -- "host process: alive"
  else
    print -r -- "host process: down"
  fi
  if [[ -n "$tun_pid" ]] && kill -0 "$tun_pid" 2>/dev/null; then
    print -r -- "tunnel process: alive"
  else
    print -r -- "tunnel process: down"
  fi
  PYTHONPATH="$src" python3 -c '
import os, sys, json
from urllib.request import Request, urlopen
from protocol import read_token, HOST_PORT, FACADE_PORT
token = read_token()
def probe(port, path="/health"):
    req = Request("http://127.0.0.1:%s%s" % (port, path), headers={"Authorization": "Bearer %s" % token})
    try:
        with urlopen(req, timeout=1.5) as resp:
            return resp.read().decode()
    except Exception as exc:
        return "unreachable: %s" % exc
print("host /health:", probe(HOST_PORT))
' || true
  command sf ws ssh "$id" --command 'python3 - <<"PY"
import json
from urllib.request import Request, urlopen
try:
    token = open("/home/%s/.local/share/cws-host-mcp/token" % __import__("os").environ.get("USER","")).read().strip()
except Exception:
    token = open(__import__("os").path.expanduser("~/.local/share/cws-host-mcp/token")).read().strip()
req = Request("http://127.0.0.1:18765/health", headers={"Authorization": "Bearer %s" % token})
try:
    print("facade /health:", urlopen(req, timeout=1.5).read().decode())
except Exception as exc:
    print("facade /health: unreachable:", exc)
PY'
}

_cws_host_down() {
  local id="$1" state pid
  state="$(_cws_host_state)"
  pid="$(cat "${state}/tunnel-${id}.lock" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    _cws_host_wait_pid_dead "$pid"
    print -r -- "connect: stopped tunnel pid ${pid} for ${id}"
  else
    print -r -- "connect: no tunnel process for ${id}"
  fi
  PYTHONPATH="$(_cws_host_src)" python3 "$(_cws_host_src)/tunnel.py" --cancel-only --workspace "$id" || true
}
