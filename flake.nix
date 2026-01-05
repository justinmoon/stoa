{
  description = "Stoa - A tiling window manager for AI-driven software development on macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    flake-utils,
    zig,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        zig-pkg = zig.packages.${system}."0.15.2";
      in {
        devShells.default = pkgs.mkShell.override {
          stdenv = pkgs.stdenvNoCC;
        } {
          name = "stoa-dev";
          packages = [
            zig-pkg
            pkgs.just
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.DarwinTools
          ];

          shellHook = ''
            ${pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              export PATH="/usr/bin:$PATH"
              unset SDKROOT
              unset DEVELOPER_DIR
            ''}
            echo "Stoa development environment"
            echo "Zig version: $(zig version)"
            echo "Just version: $(just --version)"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
