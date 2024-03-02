{
  description = "A nvim-fx flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    pre-commit-hooks-nix.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;
    systems = ["aarch64-linux" "x86_64-linux"];
    pkgsFor = lib.genAttrs systems (system:
      import nixpkgs {
        inherit system;
        overlays = [inputs.devshell.overlays.default];
      });
    forEachSystem = f: lib.genAttrs systems (system: f pkgsFor.${system});
  in {
    formatter = forEachSystem (pkgs: pkgs.alejandra);
    checks = forEachSystem (pkgs: {
      pre-commit-hooks = inputs.pre-commit-hooks-nix.lib.${pkgs.system}.run {
        src = ./.;
        hooks = {
          alejandra.enable = true;
          editorconfig-checker.enable = true;
          deadnix.enable = true;
          nil.enable = true;
          lua-ls.enable = true;
          statix.enable = true;
          stylua.enable = true;
        };
        settings = {
          lua-ls.config = lib.importJSON ./.luarc.json;
          lua-ls.checklevel = "Error";
        };
      };
    });
    devShells = forEachSystem (
      pkgs:
        with pkgs; {
          default = devshell.mkShell {
            packages = [
              alejandra
              deadnix
              lua-language-server
              nil
              statix
              stylua
            ];
            devshell.startup.pre-commit-hooks.text = "${self.checks.${pkgs.system}.pre-commit-hooks.shellHook}";
          };
        }
    );
  };
}
