#!/bin/sh

echo "Starting Homebrew utility installation..."
echo "----------------------------------------"

# --- Update Homebrew first ---
echo "Updating Homebrew..."
brew update
echo "----------------------------------------"

# --- Trust third-party taps needed below ---
# aerospace (cask) lives in nikitabobko/tap; brew now refuses untrusted-tap
# installs by default.
brew trust nikitabobko/tap
echo "----------------------------------------"

# --- Install Brew Packages (Command Line Utilities) ---
echo "Installing core CLI utilities..."
brew install \
    atuin \
    bash \
    bat \
    borders \
    cmake \
    delta \
    delve \
    direnv \
    eza \
    fd \
    ffmpeg \
    fzf \
    gcc \
    go \
    golangci-lint \
    jenv \
    jq \
    k9s \
    lazygit \
    lua \
    luajit \
    maven \
    neovim \
    node \
    parallel \
    prettier \
    ripgrep \
    sketchybar \
    stow \
    stylua \
    tmux \
    tree \
    tree-sitter \
    uv \
    watch \
    wget \
    withgraphite/tap/graphite \
    yarn \
    yazi \
    yq \
    zoxide \
    aerospace \
    font-hack-nerd-font \
    kitty \
    monitorcontrol \
    scroll-reverser \

# goimports (used by null-ls formatting in nvim's lsp.lua) has no brew formula —
# nixpkgs bundled it under `gotools`. Install it once `go` is on PATH:
#   go install golang.org/x/tools/cmd/goimports@latest
