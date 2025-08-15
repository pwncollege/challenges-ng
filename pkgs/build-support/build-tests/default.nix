{ pkgs }:
challengeSet: # This is either a nested set of challenges, or a single challenge
let
  mapTestConfig =
    v:
    if !builtins.isAttrs v then
      abort "Expected an attribute set, got: ${builtins.toJSON v}"
    else if builtins.hasAttr "type" v && v.type == "challenge" then
      {
        name = "${v.name}";
        runtime = "${pkgs.lib.getExe v.runtime}";
        tests = map (test: "${pkgs.lib.getExe test}") v.tests;
      }
    else
      builtins.mapAttrs (_: x: mapTestConfig x) v;

  testConfigJSON = pkgs.writeText "test-config.json" (builtins.toJSON (mapTestConfig challengeSet));

  python = pkgs.python3.withPackages (ps: with ps; [ rich ]);
in
pkgs.writeShellApplication {
  name = "test";
  text = ''
    ${pkgs.lib.getExe python} ${./test.py} --config ${testConfigJSON}
  '';
}
