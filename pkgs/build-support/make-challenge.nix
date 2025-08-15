{ pkgs }:
{
  name,
  files ? [ ],
  additionalFiles ? [ ],
  entrypoint ? null,
  tests ? [ ],
  meta ? { },
}@challenge:
let
  challenge = {
    inherit
      name
      files
      additionalFiles
      entrypoint
      tests
      meta
      ;
  };
  buildRuntime = pkgs.callPackage ./build-runtime.nix { };
in
{
  type = "challenge";
  name = challenge.name;
  runtime = buildRuntime challenge;
  tests = challenge.tests;
  meta = challenge.meta;
}
