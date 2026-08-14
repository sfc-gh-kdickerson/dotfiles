# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# Skip when Cursor Agent runs — fancy prompts break its shell compatibility.
if [[ -z "$CURSOR_AGENT" ]] && [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# p10k — disable when Cursor Agent runs
if [[ -n "$CURSOR_AGENT" ]]; then
  # Skip theme initialization for better compatibility
else
  zinit ice depth"1" lucid; zinit light romkatv/powerlevel10k
  [[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh
fi

# plugins
zinit ice wait"1" lucid; zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit ice wait"1" lucid; zinit light zsh-users/zsh-autosuggestions
zinit ice wait"1" lucid; zinit light ptavares/zsh-direnv
fpath+=~/.zsh/completions
autoload -Uz compinit
compinit -D
zinit ice wait"1" lucid; zinit light Aloxaf/fzf-tab

# zinit ice as"command" from"gh-r" bpick"atuin-*.tar.gz" mv"atuin*/atuin -> atuin" \
#     atclone"./atuin init zsh > init.zsh; ./atuin gen-completions --shell zsh > _atuin" \
#     atpull"%atclone" src"init.zsh"
if type -p atuin > /dev/null; then
    zinit light atuinsh/atuin
fi

ZVM_VI_ESCAPE_BINDKEY=jj
zinit ice depth"1" lucid; zinit light jeffreytse/zsh-vi-mode
function zvm_after_init() {
    # need this so atuin keybind doesn't get overridden by zvm
    bindkey '^R' atuin-search
}

# Oh My Zsh snippets
zinit snippet OMZP::aws
zinit snippet OMZP::colored-man-pages
zinit snippet OMZP::git
zinit snippet OMZP::sudo

# History
HISTFILE=~/.zsh_history
HISTSIZE=50000                # Increase the number of commands to remember in memory
SAVEHIST=$HISTSIZE            # Increase the number of commands to save in the history file
HISTDUP=erase                 # Erase duplicate history
setopt HIST_IGNORE_DUPS       # Ignore duplicate commands
setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate commands and keep the most recent
setopt HIST_FIND_NO_DUPS      # Do not display duplicates when searching history
setopt HIST_SAVE_NO_DUPS      # Do not write duplicate commands to the history file
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming history
setopt SHARE_HISTORY          # Share history across all zsh sessions
setopt INC_APPEND_HISTORY     # Append commands to history file incrementally
setopt EXTENDED_HISTORY       # Save the timestamp of commands in the history file
setopt APPEND_HISTORY         # Save the timestamp of commands in the history file

# Styling
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# path
prependToPath() {
    PATH="$1:$PATH"
}
appendToPath() {
    PATH="$PATH:$1"
}
# order will be homebrew, rust, go, normal, conda
prependToPath "$HOME/go/bin"
prependToPath "$HOME/firstpass/bin"
prependToPath "$HOME/.local/bin"
prependToPath "$HOME/.cargo/bin:$PATH"
prependToPath "/opt/homebrew/bin"
appendToPath "$HOME/miniconda3/bin"

# exports
export FZF_TMUX_OPTS='-p80%,60%'
export FZF_DEFAULT_OPTS=" \
    --color=bg+:#313244,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
export EDITOR="nvim"     
export K9S_EDITOR="nvim"    # option for k9s
export KUBE_EDITOR="nvim"   # option for k9s
export XDG_CONFIG_HOME="$HOME/.config"
export ZVM_VI_EDITOR="nvim"

# Source all .sh files from ~/.zshrc.d
if [ -d "$HOME/.zshrc.d" ]; then
  for file in "$HOME/.zshrc.d"/*.sh; do
    [ -r "$file" ] && source "$file"
  done
fi

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"

# sfid
eval "$(sf aliases)"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/kdickerson/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/kdickerson/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/kdickerson/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/kdickerson/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Added by the Cortex Code installer.
export PATH="/Users/kdickerson/.local/bin:$PATH"

alias coco="cortex"
alias cc="CLAUDE_CODE_EFFORT_LEVEL=auto ENABLE_TOOL_SEARCH=true sf ai claude -- --dangerously-skip-permissions --model 'claude-sonnet-5[1m]'"
# alias cc="claude --effort max --dangerously-skip-permissions"
alias ca="agent --yolo"
alias cx="sf ai codex --yolo"

# Cortex CLI completion (disable via /settings in cortex)
[[ -s ~/.zsh/completions/cortex.zsh ]] && source ~/.zsh/completions/cortex.zsh

# bun completions
[ -s "/Users/kdickerson/.bun/_bun" ] && source "/Users/kdickerson/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export JIRA_URL="https://snowflakecomputing.atlassian.net"
export JIRA_USERNAME="kaleb.dickerson@snowflake.com"

# Added by sf setup
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# opencode
export PATH=/home/kdickerson/.opencode/bin:$PATH
