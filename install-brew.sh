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
    bat \
    borders \
    cmake \
    eza \
    fd \
    ffmpeg \
    fzf \
    gcc \
    jenv \
    jq \
    k9s \
    lua \
    luajit \
    maven \
    neofetch \
    neovim \
    parallel \
    ripgrep \
    sketchybar \
    stow \
    stylua \
    tmux \
    tree-sitter \
    watch \
    wget \
    yazi \
    yq \
    zoxide \
    aerospace \
    font-hack-nerd-font \
    kitty \
    monitorcontrol \
    scroll-reverser \

