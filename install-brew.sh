#!/bin/sh

echo "Starting Homebrew utility installation..."
echo "----------------------------------------"

# --- Update Homebrew first ---
echo "Updating Homebrew..."
brew update
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
    direnv \
    eza \
    fd \
    ffmpeg \
    fzf \
    gcc \
    go \
    jenv \
    jq \
    k9s \
    lazygit \
    lua \
    luajit \
    maven \
    neofetch \
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

