{
  description = "A collection of pwn.college challenges";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [
                (self: super: {
                  makeChallenge = super.callPackage ./pkgs/build-support/make-challenge.nix { };
                  makePrivileged = super.callPackage ./pkgs/build-support/make-privileged.nix { };
                  renderJinja = super.callPackage ./pkgs/build-support/render-jinja.nix { };
                  execSuid = super.callPackage ./pkgs/build-support/exec-suid.nix { };
                  lib = super.lib.extend (
                    final: prev: {
                      maintainers = final.lib.maintainers // import ./maintainers;
                    }
                  );
                })
                (self: super: {
                  codex = (import nixpkgs-unstable { inherit system; }).codex;
                })
              ];
            };
          in
          f pkgs
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          challenges = import ./pkgs/challenges { inherit pkgs; };

          mapChallengeRuntimes =
            v:
            if !builtins.isAttrs v then
              abort "Expected an attribute set, got: ${builtins.toJSON v}"
            else if builtins.hasAttr "type" v && v.type == "challenge" then
              v.runtime
            else
              builtins.mapAttrs (_: x: mapChallengeRuntimes x) v;

          buildTests = pkgs.callPackage ./pkgs/build-support/build-tests { };

          mapChallengeTests =
            v:
            if !builtins.isAttrs v then
              abort "Expected an attribute set, got: ${builtins.toJSON v}"
            else if builtins.hasAttr "type" v && v.type == "challenge" then
              buildTests v
            else
              buildTests v // builtins.mapAttrs (_: x: mapChallengeTests x) v;
        in
        {
          challenges = {
            runtime = mapChallengeRuntimes challenges;
            tests = mapChallengeTests challenges;
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            codex
            git
            nixfmt-tree
            python3
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
