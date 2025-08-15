{ pkgs }:

let
  helloTest = pkgs.writeShellApplication {
    name = "test-hello";
    text = ''
      output=$(hello)
      echo "$output"
      [[ "$output" == *"Hello, World!"* ]]
    '';
  };
in
{
  hello-shell =
    let
      program = pkgs.writeShellApplication {
        name = "hello";
        text = ''
          echo "Hello, World! The flag is: $(cat /flag)."
        '';
      };
    in
    pkgs.makeChallenge {
      name = "hello-shell";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple shell challenge that prints the flag.

          This creates a challenge with a single shell script, "hello", that prints the flag.
          This program is made available in the PATH at both /bin/hello and /usr/local/bin/hello, allowing users to easily discover and run it.
          Critically, the program is made "privileged" so that it can have the necessary permissions to read the flag.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-shell-cow =
    let
      program = pkgs.writeShellApplication {
        name = "hello";
        runtimeInputs = [ pkgs.cowsay ];
        text = ''
          cowsay "Hello, World! The flag is: $(cat /flag)."
        '';
      };
    in
    pkgs.makeChallenge {
      name = "hello-shell-cow";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple shell challenge where a cow says the flag.

          In this example, we specify runtime inputs for our shell script to ensure that all necessary dependencies are available when the program runs.
          These dependencies are not added to the user's PATH, as they are considered implementation details rather than part of the challenge interface.
          While advanced users might inspect these dependencies to gain deeper insight into the challenge, doing so is not required or expected for solving it.
          By keeping such dependencies hidden, we help maintain a simple and focused challenge environment.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-python =
    let
      program = pkgs.writeScriptBin "hello" ''
        #!${pkgs.python3}/bin/python
        flag = open("/flag").read().strip()
        print(f"Hello, World! The flag is: {flag}.")
      '';
    in
    pkgs.makeChallenge {
      name = "hello-python";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple python challenge that prints the flag.

          This challenge shows how to create a simple privileged python program that prints the flag.
          The program is made privileged, and the shebang line is automatically patched to ensure it runs securely with the required permissions.
          You can adapt this pattern for other interpreters, such as ruby or perl; however, note that runtimes other than python and bash may require additional steps to ensure the interpreter is properly secured.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-python-rich =
    let
      pythonRich = pkgs.python3.withPackages (
        ps: with ps; [
          rich
        ]
      );
      program = pkgs.writeScriptBin "hello" ''
        #!${pythonRich}/bin/python

        from rich.console import Console
        from rich.text import Text

        console = Console()
        flag = open("/flag").read().strip()

        text = Text.assemble(
            ("Hello, World!", "bold blue"),
            (" The flag is: ", ""),
            (flag, "bold magenta"),
            (".", ""),
        )
        console.print(text)
      '';
    in
    pkgs.makeChallenge {
      name = "hello-python-rich";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple python challenge that, richly, prints the flag.

          This challenge demonstrates how to specify and include python dependencies, ensuring the program has everything it needs to run.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-entrypoint =
    let
      entrypoint = pkgs.writeShellApplication {
        name = "entrypoint";
        text = ''
          cp --no-preserve=mode,ownership /flag /tmp/flag
        '';
      };
    in
    pkgs.makeChallenge {
      name = "hello-entrypoint";
      files = [ entrypoint ];
      inherit entrypoint;
      tests = [
        (pkgs.writeShellApplication {
          name = "test-hello-entrypoint";
          text = ''
            cat /tmp/flag
          '';
        })
      ];
      meta = with pkgs.lib; {
        description = ''
          A simple challenge where the entrypoint script copies the flag to /tmp/flag.

          Notice that there is not a "privileged" program here.
          Instead the entrypoint script, which always runs privileged, immediately performs all of the necessary privileged actions to complete the challenge.
          We include the entrypoint in the challenge files, so that this behavior can be easily discovered; but this is not required.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-server =
    let
      pythonFlask = pkgs.python3.withPackages (
        ps: with ps; [
          flask
        ]
      );
      server = pkgs.writeScriptBin "server" ''
        #!${pythonFlask}/bin/python

        from flask import Flask

        app = Flask(__name__)
        flag = open("/flag").read().strip()

        @app.route('/')
        def hello():
            return f"Hello, World! The flag is: {flag}.\n"

        if __name__ == '__main__':
            app.run(host='0.0.0.0', port=8080)
      '';
      entrypoint = pkgs.writeShellApplication {
        name = "entrypoint";
        runtimeInputs = with pkgs; [
          daemonize
          curl
        ];
        text = ''
          STATE_DIR=/tmp/hello-server
          mkdir -p "$STATE_DIR"
          daemonize \
            -p "$STATE_DIR/server.pid" \
            -o "$STATE_DIR/server.log" \
            -e "$STATE_DIR/server.err" \
            ${server}/bin/server
          until curl -s http://localhost:8080/ > /dev/null; do
            sleep 0.1
          done
        '';
      };
    in
    pkgs.makeChallenge {
      name = "hello-server";
      files = [
        server
        entrypoint
      ];
      additionalFiles = with pkgs; [ curl ];
      inherit entrypoint;
      tests = [
        (pkgs.writeShellApplication {
          name = "test-hello-server";
          text = ''
            output=$(curl -s http://localhost:8080/)
            echo "$output"
            [[ "$output" == *"Hello, World!"* ]]
          '';
        })
      ];
      meta = with pkgs.lib; {
        description = ''
          A simple server challenge that prints the flag.

          The server is started in the background using daemonize within the entrypoint script.
          We include curl as an "additional" file to provide users with a convenient tool for interacting with the server.
          "Additional" files are placed in /usr/local/bin, making them available in the PATH without cluttering /bin, which is reserved for core challenge binaries.
          This separation allows challenge authors to offer helpful utilities to users while keeping the main environment focused.
          Note that challenge dependencies (such as python, flask, etc.) are not included as "additional" files—-only user-facing tools intended for direct use are provided here.
          The challenge environment already includes several common utilities in /usr/bin by default; however, by explicitly including curl, we ensure it is available and takes precedence over any other program with the same name, such as a different version of curl.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-c =
    let
      src = pkgs.writeText "hello.c" ''
        #include <stdio.h>
        #include <stdlib.h>

        int main() {
            char *flag = NULL;
            FILE *file = fopen("/flag", "r");
            if (!file) { perror("Failed to open /flag"); return 1; }
            getline(&flag, &(size_t){0}, file);
            fclose(file);
            printf("Hello, World! The flag is: %s", flag);
            free(flag);
            return 0;
        }
      '';
      program = pkgs.runCommandCC "hello" { } ''
        mkdir -p $out/bin
        $CC ${src} -o $out/bin/hello
      '';
    in
    pkgs.makeChallenge {
      name = "hello-c";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple C challenge that prints the flag.
        '';
        maintainers = [ maintainers.connor ];
      };
    };

  hello-render-jinja =
    let
      template = pkgs.writeText "hello.j2" ''
        {%- for greeting in greetings -%}
        echo -n '{{ greeting }}! '
        {% endfor -%}
        echo "The flag is: $(cat /flag)."
      '';
      program = pkgs.writeShellApplication {
        name = "hello";
        text = builtins.readFile (pkgs.renderJinja template { greetings = [ "Hello, World" ]; });
      };
    in
    pkgs.makeChallenge {
      name = "hello-render-jinja";
      files = with pkgs; [ (makePrivileged program) ];
      tests = [ helloTest ];
      meta = with pkgs.lib; {
        description = ''
          A simple templated challenge that prints the flag.
        '';
        maintainers = [ maintainers.connor ];
      };
    };
}
