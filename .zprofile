# Login shells only. GLOBAL_RCS is unset on Cloud Workspaces (see ~/.zshenv),
# so pull /etc/zprofile in ourselves (PATH=$HOME/bin and /etc/profile).
if [[ -d /etc/cloudws && -r /etc/zprofile ]]; then
  # /etc/profile.d/snowflake-00-default.sh runs sync-creds in the foreground (~4s)
  # unless this is set. Rex panes never inherit it, so sync in the background.
  if [[ -o interactive && -z ${_SF_CREDS_SYNCED:-} ]]; then
    export _SF_CREDS_SYNCED=1
    (TERM=dumb command sf __cwagent sync-creds --max-stale 6h --min-cert-ttl 1h >/dev/null 2>&1) &!
  fi
  # snowflake-00-default.sh also evals `sf auth aliases` (~120ms). ~/.zshrc
  # sources the same output from a cache, so answer it with nothing here.
  sf() {
    [[ $1 == auth && $2 == aliases ]] && return 0
    command sf "$@"
  }
  source /etc/zprofile
  unfunction sf
fi

# Machine-local login PATH and env; not tracked.
[[ -r $HOME/.zprofile.local ]] && source "$HOME/.zprofile.local"
