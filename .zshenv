# Matches the prefix in ~/.npmrc without launching npm on every shell startup.
export PATH="$HOME/.npm-global/bin:$PATH"

# Cloud Workspaces: skip /etc/zshrc. It re-runs python git-repo init, `sf auth
# aliases`, a bazel clang find, direnv, and a second compinit on every pane
# (~180ms). ~/.zshrc.d/cws.sh reapplies the bits we still need, cheaply.
# Login shells still source /etc/zprofile from ~/.zprofile.
if [[ -d /etc/cloudws ]]; then
  unsetopt GLOBAL_RCS
fi
