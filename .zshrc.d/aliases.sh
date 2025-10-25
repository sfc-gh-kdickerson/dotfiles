# General aliases
alias k="kubectl"
alias v="nvim"
alias c="clear"
alias y="yazi"
alias fzf="fzf-tmux -p"
alias fzfp="fzf-tmux -p --preview 'bat --color=always {}' --preview-window '~3'"
alias ls="eza"
alias cat="bat --paging=never"

man() {
  nvim +"Man $* | only"
}
cdi() {
    __zoxide_zi
}
mkcd() {
    mkdir $1
    cd $1
}
tcopy() {
    word=$(tmux capture-pane -J -p | tr -s '[:space:]' '\n' | fzf)
    if [ -n "$word" ]; then
        echo "$word" | pbcopy
    fi
}
vconfig() {
    cd ~/.config/nvim
    nvim .
}
zconfig() {
    nvim ~/.zshrc
}

# kubectl aliases
knsset() {
    kubectl config set-context --current --namespace=$1
}
knsget() {
  local namespace
  namespace=$(kubectl config view --minify --output 'jsonpath={..namespace}')
  if [[ -z "$namespace" ]]; then
    echo "default"
  else
    echo "$namespace"
  fi
}
kns() {
    ns=$(k get ns | awk 'NR > 1 {print $1}' | sort | fzf --header="Select namespace")
    if [ -n "$ns" ]; then
        kubectl config set-context --current --namespace=$ns
    fi
}
ka() {
    command=$1
    resource=$2
    names=$(k get $resource | awk 'NR > 1 {print $1}' | fzf -m --header="Pick resources")
    if [ -n "$names" ]; then
        echo "running: kubectl $command $resource $names"
        kubectl $command $resource $names
    fi
}
klog() {
    pod=$(kubectl get pods --all-namespaces -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers | fzf --header="Select a pod to tail logs")
    if [ -z "$pod" ]; then
        echo "No pod selected."
        return
    fi
    namespace=$(echo $pod | awk '{print $2}')
    pod_name=$(echo $pod | awk '{print $1}')
    kubectl logs -f -n $namespace $pod_name | tspin
}
kctx() {
    cluster=$(kubectl config get-contexts | awk 'NR > 1 {print $2}' | sort | uniq | fzf --header="Select cluster to set in kubectl context")
    if [ -n "$cluster" ]; then
        kubectl config use-context $cluster
    fi
}
