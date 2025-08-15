{ pkgs }:
file: variables:
let
  variablesJSON = pkgs.writeText "template-variables.json" (builtins.toJSON variables);
in
pkgs.runCommand "rendered-${baseNameOf file}" { nativeBuildInputs = [ pkgs.jinja2-cli ]; } ''
  jinja2 --strict ${file} ${variablesJSON} > $out
''
