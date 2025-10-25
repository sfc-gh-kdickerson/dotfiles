# This flake provides a user-level set of packages.
{
  description = "My user-level packages";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; config = { allowUnfree = true; }; };
        lib = pkgs.lib;

        commonPackages = with pkgs; [
            atuin
            bash
            bat
            cargo
            direnv
            eza
            fzf
            delta
            go
            jq
            neovim
            nodejs_20
            ripgrep
            stow
            stylua
            tmux
            tree
            tree-sitter
            watch
            wget
            yarn
            yazi
            zoxide
        ];

        darwinPackages = with pkgs; [
            jankyborders
            sketchybar
        ];

        linuxPackages = with pkgs; [
        ];

      in
      {
        packages.default = pkgs.buildEnv {
          name = "my-user-packages";
          paths = 
            commonPackages 
            ++ lib.optionals pkgs.stdenv.isDarwin darwinPackages 
            ++ lib.optionals pkgs.stdenv.isLinux linuxPackages;
        };
      }
    );
}
