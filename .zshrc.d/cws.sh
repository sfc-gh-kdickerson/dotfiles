# Fast Cloud Workspace interactive env. Replaces /etc/zshrc's CWS block after
# GLOBAL_RCS is unset in ~/.zshenv. No-op off-workspace (and on the Mac).
[[ -d /etc/cloudws ]] || return
[[ -o interactive ]] || return

() {
  export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"
  export PRE_COMMIT_HOME="${PRE_COMMIT_HOME:-/home/repo/pre-commit/cache}"

  # wrap_cli must precede the real binaries it wraps.
  [[ -d /usr/local/bin/wrap_cli ]] && path=(/usr/local/bin/wrap_cli $path)
  [[ -d "$HOME/Snowflake/trunk/ExecPlatform/bin" ]] && path+="$HOME/Snowflake/trunk/ExecPlatform/bin"

  # Honor an already-resolved clang; otherwise the known toolchain path.
  # /etc/zshrc finds under /scratch/bazel every pane (~20ms).
  if ! (( $+commands[clang] )); then
    local clang_dir="/scratch/bazel/36bac8ee52e5d1559627454b12aa1b28/external/_main~_repo_rules~clang-22.1.0-$(uname -p)"
    [[ -d "$clang_dir/bin" ]] && path+="$clang_dir/bin"
  fi

  [[ -S "/dev/shm/ssh-agent-${USER}.sock" ]] && export SSH_AUTH_SOCK="/dev/shm/ssh-agent-${USER}.sock"

  [[ -r /etc/cloudws/init-creds.sh ]] && source /etc/cloudws/init-creds.sh

  # Creds sync is once-per-session in tmux env; if unset, do not block the prompt.
  if [[ -z ${_SF_CREDS_SYNCED:-} ]]; then
    export _SF_CREDS_SYNCED=1
    (TERM=dumb command sf __cwagent sync-creds --max-stale 6h --min-cert-ttl 1h >/dev/null 2>&1) &!
  fi

  local f
  for f in /etc/cloudws/profile.d/*.sh; do
    [[ -r $f ]] && source "$f"
  done

  # Python startup is ~37ms even when init is already done.
  if [[ -e /etc/cloudws_customization/git_repo_init.py && ! -e /etc/cloudws_customization/.git_repo_init_done ]]; then
    /opt/sfc/python3.11/bin/python3.11 /etc/cloudws_customization/git_repo_init.py
  fi

  bindkey ' ' magic-space 2>/dev/null || true
  bindkey '^[[3~' delete-char 2>/dev/null || true

  # Graphite completion: our .zshrc already ran compinit. Do not run it again.
  if (( $+commands[gt] )); then
    autoload -U +X bashcompinit && bashcompinit
    local gt_cache="${XDG_RUNTIME_DIR:-/tmp/${USER}}/gt_completion_cache.zsh"
    if [[ ! -f $gt_cache ]]; then
      mkdir -p "${gt_cache:h}"
      command gt completion >|"$gt_cache" 2>/dev/null || true
    fi
    [[ -r $gt_cache ]] && source "$gt_cache"
  fi

  # CWS deploys ~/.zshrc.d/*.zsh (home-manager auto-apply). Our loop only sources *.sh.
  for f in "$HOME/.zshrc.d"/*.zsh; do
    [[ -r $f ]] && source "$f"
  done

  [[ -r /nix/var/nix/profiles/default/share/nix-direnv/direnvrc ]] && source /nix/var/nix/profiles/default/share/nix-direnv/direnvrc
}
