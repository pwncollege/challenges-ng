{ pkgs }:
challenge:
let
  filesystem = pkgs.callPackage ./build-filesystem.nix { } challenge;
in
pkgs.writeShellApplication {
  name = "run-${challenge.name}";

  runtimeInputs = with pkgs; [
    coreutils
    gnutar
    gzip
    jq
    runc
  ];

  text = ''
    flag="''${FLAG:-}"
    if [ -z "$flag" ]; then
      echo "Error: FLAG is not set."
      exit 1
    fi

    bundle=$(mktemp -d)
    trap 'rm -rf "$bundle"' EXIT

    if [ "$#" -gt 0 ]; then
      additionalProcessArgs="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
    else
      additionalProcessArgs="[]"
    fi

    jq --argjson additionalProcessArgs "$additionalProcessArgs" \
      '.process.args += $ARGS.named.additionalProcessArgs' \
      ${filesystem}/config.json > "$bundle/config.json"

    mkdir -p "$bundle/rootfs"
    tar -xzf ${filesystem}/rootfs.tar.gz -C "$bundle/rootfs"

    echo "$flag" > "$bundle/rootfs/flag"
    chmod 0400 "$bundle/rootfs/flag"

    runc run --bundle "$bundle" "challenge-${challenge.name}"
    exit $?
  '';

  meta = challenge.meta;
}
