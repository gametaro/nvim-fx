{
  description = "A nvim-fx flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks-nix = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.pre-commit-hooks-nix.flakeModule
        inputs.devshell.flakeModule
      ];

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      perSystem = {
        config,
        inputs',
        pkgs,
        ...
      }: {
        pre-commit = {
          settings = {
            hooks = {
              actionlint.enable = true;
              alejandra.enable = true;
              editorconfig-checker.enable = true;
              lua-ls.enable = false;
              nil.enable = true;
              statix.enable = true;
              stylua.enable = true;
              yamllint.enable = true;
            };
          };
        };

        devshells.default = {
          packages = with pkgs; [
            actionlint
            alejandra
            editorconfig-checker
            lua-language-server
            nil
            statix
            stylua
            yaml-language-server
          ];
          devshell = {
            motd = "";
            startup.pre-commit.text = "${config.pre-commit.installationScript}";
          };
        };
      };
    };
}
