# Login shells only. GLOBAL_RCS is unset on Cloud Workspaces (see ~/.zshenv),
# so pull /etc/zprofile in ourselves (PATH=$HOME/bin and /etc/profile).
if [[ -d /etc/cloudws && -r /etc/zprofile ]]; then
  source /etc/zprofile
fi
