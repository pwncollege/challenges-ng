import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, TimeElapsedColumn
from rich.table import Table


console = Console()


def only_messages(text):
    messages = []
    for line in text.splitlines():
        line = line.rstrip()
        if not line:
            messages.append("")
            continue

        # JSON log lines: {"time":..., "level":..., "msg": "..."}
        if line.startswith("{") and line.endswith("}"):
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    if isinstance(obj.get("msg"), str):
                        messages.append(obj["msg"])
                        continue
                    if isinstance(obj.get("message"), str):
                        messages.append(obj["message"])
                        continue
            except json.JSONDecodeError:
                pass

        # logfmt style: time=... level=... msg="..."
        match = re.search(r'msg=(?:"([^"]*)"|\'([^\']*)\'|([^\s]+))', line)
        if match:
            value = next((g for g in match.groups() if g is not None), "")
            messages.append(value)
            continue

        # Common prefixes: timestamp + level, or [LEVEL], or LEVEL: ...
        patterns = [
            r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?\s+-\s+[A-Z]+\s+-\s+',
            r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[\.,]\d+)?\s+',
            r'^\[[A-Z]+\]\s+',
            r'^(DEBUG|INFO|WARN|WARNING|ERROR|CRITICAL)\s*[:\-]\s+',
        ]
        stripped = line
        for pattern in patterns:
            candidate = re.sub(pattern, '', stripped)
            if candidate != stripped:
                stripped = candidate
                break
        messages.append(stripped)

    return "\n".join(messages)


def run_one(runtime, test_program):
    start = time.perf_counter()
    flag = "FLAG{" + os.urandom(16).hex() + "}"
    try:
        proc = subprocess.run(
            [runtime, test_program],
            env={"FLAG": flag},
            text=True,
            capture_output=True,
            check=False
        )
    except FileNotFoundError as exc:
        return {
            "name": pathlib.Path(test_program).name,
            "status": "error",
            "duration": time.perf_counter() - start,
            "flag": False,
            "output": str(exc),
        }

    output = proc.stdout + proc.stderr
    return {
        "name": pathlib.Path(test_program).name,
        "status": "pass" if proc.returncode == 0 else "fail",
        "duration": time.perf_counter() - start,
        "flag": flag in output,
        "output": output,
        "returncode": proc.returncode,
    }


def iter_tests(cfg):
    stack = [("", cfg)]
    while stack:
        prefix, node = stack.pop()
        if "runtime" in node:  # leaf
            for test_program in node.get("tests", []):
                label = prefix.rstrip(".") or node.get("name", "challenge")
                yield label, node["runtime"], test_program
        else:
            for key, child in node.items():
                stack.append((f"{prefix}{key}.", child))


def main():
    parser = argparse.ArgumentParser(description="Run challenge tests")
    parser.add_argument("--config", "-c", default="test-config.json", help="Path to test-config JSON")
    parser.add_argument("--flag", default=os.environ.get("FLAG", "FLAG"), help="Flag string to detect in output")
    parser.add_argument("--jobs", "-j", type=int, default=os.cpu_count(), help="Parallel jobs (default: CPU count)")
    args = parser.parse_args()

    try:
        config = json.load(open(args.config, "r", encoding="utf-8"))
    except FileNotFoundError:
        console.print(f"[bold red]Error:[/] cannot open config file {args.config}")
        sys.exit(1)

    tests = list(iter_tests(config))
    summary = {"pass": 0, "fail": 0, "error": 0, "flag": 0}

    table = Table(title="Challenge Test Results", show_lines=True)
    table.add_column("Challenge", style="cyan", overflow="fold")
    table.add_column("Test", overflow="fold")
    table.add_column("Result", style="bold")
    table.add_column("Time (ms)", justify="right")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        TimeElapsedColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Running tests", total=len(tests))
        results = []
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {
                pool.submit(run_one, runtime, test_program): (label, test_program)
                for label, runtime, test_program in tests
            }
            for future in as_completed(futures):
                challenge_label, test_program = futures[future]
                result = future.result()

                test_name = pathlib.Path(test_program).name

                flag_symbol = "🚩" if result["flag"] else " "
                status = {
                    "pass": "[green]✓ Pass[/]",
                    "fail": "[red]✗ Fail[/]",
                    "error": "[red]⚠ Error[/]",
                }[result["status"]]
                result_text = f"{flag_symbol} {status}"

                millis = int(result["duration"] * 1000)

                table.add_row(
                    challenge_label,
                    test_name,
                    result_text,
                    str(millis),
                )

                summary[result["status"]] += 1
                if result["flag"]:
                    summary["flag"] += 1

                progress.advance(task)

                # Capture for detailed reporting after the table
                results.append({
                    "challenge": challenge_label,
                    "test": test_name,
                    **result,
                })

    console.print(table)
    console.rule()

    if summary["fail"] == 0 and summary["error"] == 0:
        console.print(f"[bold green]{summary['pass']} tests passed[/]", justify="center")
    else:
        failures = summary["fail"] + summary["error"]
        console.print(f"[bold red]{failures} tests failed[/]", justify="center")

    if summary["flag"]:
        console.print(f"[bold green]🚩 Flag detected in {summary['flag']} outputs[/]")
    else:
        console.print("[bold red]🚩 Flag not detected in any output[/]")

    # When tests fail or error, show their captured output to aid debugging
    failing_outputs = [result for result in results if result.get("status") in ("fail", "error")]
    if failing_outputs:
        console.rule("[bold red]Failing Test Output[/]", style="red")
        for result in failing_outputs:
            console.rule(f"[bold]{result['challenge']} :: {result['test']}[/]", style="red")
            output_text = result.get("output", "").rstrip()
            if output_text:
                console.print(only_messages(output_text))
            else:
                console.print("[dim]<no output captured>[/]")
            console.rule("", style="red")

    if summary["fail"] or summary["error"] or summary["flag"] == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
