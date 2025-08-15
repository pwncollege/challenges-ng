# pwn.college Challenges

A collection of pwn.college challenges.
This is a work in progress (prototype) that is being developed as a next-generation way to handle developing and maintaining challenges.

## Usage

### Runtime

A challenge has a runtime that is used to run the challenge.

For example, to run the `example.hello-shell` challenge, and spawn a shell as the entrypoint, we can use the following command:
```bash
sudo -E FLAG="FLAG{this-is-an-example-flag}" nix run '.#challenges.runtime.example.hello-shell' -- bash
```

Alternatively, we can directly run the challenge's main program (`hello` in this case):
```bash
sudo -E FLAG="FLAG{this-is-an-example-flag}" nix run '.#challenges.runtime.example.hello-shell' -- /bin/hello
```

### Tests

We can run all tests for all challenges using the following command:
```bash
sudo nix run '.#challenges.tests'
```

Alternatively, we can run a specific challenge's tests:
```bash
sudo nix run '.#challenges.tests.example.hello-shell'
```
