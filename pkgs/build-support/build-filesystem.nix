{ pkgs }:
challenge:
let
  username = "user";
  home = "/home/${username}";

  entrypoint = pkgs.writeShellApplication {
    name = "${challenge.name}-entrypoint";
    runtimeInputs = with pkgs; [ util-linux ];
    text = ''
      ${pkgs.lib.optionalString (challenge.entrypoint != null) ''
        "${pkgs.lib.getExe challenge.entrypoint}" "$@"
      ''}
      if [ "$#" -gt 0 ]; then
        export USER=${username}
        export HOME=${home}
        export LC_ALL=C
        exec setpriv --reuid=${username} --regid=${username} --init-groups "$@"
      fi
    '';
  };

  runcConfig =
    let
      defaultConfig = builtins.fromJSON (
        builtins.readFile (
          pkgs.runCommand "runc-spec" { nativeBuildInputs = with pkgs; [ runc ]; } ''
            runc spec
            mv config.json $out
          ''
        )
      );
    in
    defaultConfig
    // {
      process = defaultConfig.process // {
        args = [ "${pkgs.lib.getExe entrypoint}" ];
        # terminal = false;
        capabilities =
          let
            additional_capabilities = [
              "CAP_SETUID"
              "CAP_SETGID"
              "CAP_DAC_OVERRIDE"
              "CAP_DAC_READ_SEARCH"
              "CAP_SYS_PTRACE"
            ];
          in
          pkgs.lib.mapAttrs (_: value: value ++ additional_capabilities) defaultConfig.process.capabilities;
        noNewPrivileges = false;
      };

      mounts = defaultConfig.mounts ++ [
        {
          destination = "/tmp";
          type = "tmpfs";
          source = "tmpfs";
          options = [
            "nosuid"
            "nodev"
            "size=1g"
          ];
        }
        {
          destination = "/nix/store";
          type = "bind";
          source = "/nix/store";
          options = [
            "rbind"
            "ro"
            "nosuid"
            "nodev"
          ];
        }
        {
          destination = home;
          type = "bind";
          source = "./rootfs/${home}";
          options = [
            "nosuid"
            "nodev"
            "rbind"
            "rw"
          ];
        }
      ];
    };

  runcConfigFile = pkgs.writeText "config.json" (builtins.toJSON runcConfig);

  challengeFiles = pkgs.symlinkJoin {
    name = "${challenge.name}-challenge-files";
    paths = challenge.files;
  };

  additionalFiles = pkgs.symlinkJoin {
    name = "${challenge.name}-additional-files";
    paths = challenge.additionalFiles;
  };

  standardFiles = pkgs.symlinkJoin {
    name = "standard-files";
    paths = with pkgs; [
      bashInteractive
      bzip2
      coreutils
      curl
      diffutils
      execSuid
      file
      findutils
      gawk
      gcc
      glibc.bin
      gnugrep
      gnused
      gnutar
      gzip
      inetutils
      iproute2
      jq
      less
      man-db
      man-pages
      man-pages-posix
      nano
      ncurses
      patch
      procps
      rsync
      shadow
      strace
      util-linux
      vim
      wget
      which
      xz
    ];
  };

  etcFiles =
    let
      passwd = pkgs.writeTextDir "/etc/passwd" ''
        root:x:0:0:root:/root:${pkgs.lib.getExe pkgs.bashInteractive}
        ${username}:x:1000:1000:${username},,,:${home}:${pkgs.lib.getExe pkgs.bashInteractive}
      '';
      group = pkgs.writeTextDir "/etc/group" ''
        root:x:0:
        ${username}:x:1000:
      '';
      profile = pkgs.writeTextDir "/etc/profile" ''
        export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        export LC_ALL=C
        export PS1='${username}@challenge: \w\$ '
      '';
    in
    pkgs.buildEnv {
      name = "${challenge.name}-etc-files";
      paths = [
        standardFiles
        additionalFiles
        passwd
        group
        profile
      ];
      pathsToLink = [ "/etc" ];
    };

  privilegedPaths =
    let
      privilegedFiles = pkgs.lib.filter (f: f.passthru.privileged or false) challenge.files;
      relativeTo = base: path: pkgs.lib.removePrefix "${base}" "${path}";
      paths = pkgs.lib.concatMap (
        file: map (p: relativeTo file p) (pkgs.lib.filesystem.listFilesRecursive file)
      ) privilegedFiles;
    in
    paths ++ (map (p: "/usr/local${p}") paths) ++ [ "/usr/bin/exec-suid" ];

  files =
    let
      binSh = pkgs.runCommand "bin-sh" { } ''
        mkdir -p $out/bin
        ln -s ${pkgs.lib.getExe' pkgs.bash "sh"} $out/bin/sh
      '';
      usrLocalChallengeFiles = pkgs.buildEnv {
        name = "${challenge.name}-challenge-usr-local-files";
        paths = [ challengeFiles ];
        extraPrefix = "/usr/local";
      };
      usrLocalAdditionalFiles = pkgs.buildEnv {
        name = "${challenge.name}-additional-usr-local-files";
        paths = [ additionalFiles ];
        extraPrefix = "/usr/local";
      };
      usrStandardFiles = pkgs.buildEnv {
        name = "standard-usr-files";
        paths = [ standardFiles ];
        extraPrefix = "/usr";
      };
      realPathHierarchy = # Ensure the full path hierarchy is created for privileged paths
        pkgs.runCommand "${challenge.name}-real-path-hierarchy" { } ''
          for path in ${pkgs.lib.concatStringsSep " " privilegedPaths}; do
            mkdir -p "$out/$(dirname "$path")"
          done
        '';
    in
    pkgs.buildEnv {
      name = "${challenge.name}-rootfs-files-wtf";
      paths = [
        challengeFiles
        etcFiles
        binSh
        usrLocalChallengeFiles
        usrLocalAdditionalFiles
        usrStandardFiles
        realPathHierarchy
      ];
    };

  mountpoints = pkgs.runCommand "mountpoints" { } ''
    mkdir -p $out
    ${pkgs.lib.concatMapStrings (mount: ''
      install -d "$out/${mount.destination}"
    '') runcConfig.mounts}
  '';
in
pkgs.runCommand "${challenge.name}-rootfs" { nativeBuildInputs = with pkgs; [ fakeroot ]; } ''
  mkdir -p $out

  mkdir -p rootfs
  cp -r --no-preserve=mode ${mountpoints}/* ${files}/* rootfs/

  fakeroot -- sh -eu <<'EOF'
    install -d -o1000 -g1000 "rootfs/${home}"
    install -d -m0700 "rootfs/root"
    install -d -m1777 "rootfs/tmp"
    for path in ${pkgs.lib.concatStringsSep " " privilegedPaths}; do
      echo "installing privileged path: $path" >&2
      install -o0 -g0 -m4755 $(readlink -f "rootfs/$path") "rootfs/$path"
    done
    tar --numeric-owner -czf $out/rootfs.tar.gz -C rootfs .
  EOF

  ln -s ${runcConfigFile} $out/config.json

  # Manually preserve the closure, which is lost by creating a tarball
  ln -s ${pkgs.writeClosure [ files ]} $out/.closure
''
