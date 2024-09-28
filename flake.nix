{
  description = "A nvim-fx flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (nixpkgs) lib;
    systems = ["aarch64-linux" "x86_64-linux"];
    pkgsFor = lib.genAttrs systems (system: import nixpkgs {inherit system;});
    forEachSystem = f: lib.genAttrs systems (system: f pkgsFor.${system});
  in {
    formatter = forEachSystem (pkgs: pkgs.alejandra);
    checks = forEachSystem (pkgs: {
      pre-commit-check = inputs.pre-commit-hooks.lib.${pkgs.system}.run {
        src = ./.;
        hooks = {
          alejandra.enable = true;
          editorconfig-checker.enable = true;
          deadnix.enable = true;
          nil.enable = true;
          lua-ls.enable = true;
          lua-ls.settings = {
            configuration = lib.importJSON ./.luarc.json;
            checklevel = "Error";
          };
          statix.enable = true;
          stylua.enable = true;
        };
      };
    });
    devShells = forEachSystem (
      pkgs: {
        default = pkgs.mkShellNoCC {
          inherit (self.checks.${pkgs.system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${pkgs.system}.pre-commit-check.enabledPackages;
        };
      }
    );
  };
}
