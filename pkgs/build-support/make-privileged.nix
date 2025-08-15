{ pkgs }:
drv:
pkgs.stdenv.mkDerivation {
  name = "${drv.name}-privileged";

  src = drv;
  unpackPhase = false;
  installPhase = ''
    cp -r ${drv} $out
    chmod -R u+w $out
    for file in $(find $out -type f -executable); do
      read -r shebang < "$file"
      [[ "$shebang" =~ ^#! ]] || continue
      [[ "$shebang" =~ ^#![[:space:]]*/usr/bin/exec-suid ]] && continue
      case "$shebang" in
        */bin/bash*)
          sed -i -E \
            -e '1s|^#!|#!/usr/bin/exec-suid -- |' \
            -e '1s|/bin/bash|/bin/bash -p|' \
            "$file"
          ;;
        */bin/python*)
            sed -i -E \
             -e '1s|^#!|#!/usr/bin/exec-suid -- |' \
             -e '1s|/bin/python([0-9]+(\.[0-9]+)?)?|/bin/python\1 -I|' \
             "$file"
          ;;
        *)
          echo "warning: unknown shebang in $file: $shebang" >&2
          sed -i -E \
            -e '1s|^#!|#!/usr/bin/exec-suid -- |' \
            "$file"
          ;;
      esac
    done
  '';

  passthru = (drv.passthru or { }) // {
    privileged = true;
  };
}
