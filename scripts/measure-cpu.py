#!/usr/bin/env python3
"""Read-only macOS process CPU/RSS sample. CPU is percent of one core, not battery watts."""
import argparse
import json
import subprocess
import time


def snapshot(pid):
    fields = subprocess.check_output(['ps', '-p', str(pid), '-o', 'time=,rss='], text=True).split()
    if len(fields) != 2:
        raise SystemExit('Process is not running')
    elapsed = 0.0
    for part in fields[0].split(':'):
        elapsed = elapsed * 60 + float(part)
    return elapsed, int(fields[1]) / 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pid', type=int)
    parser.add_argument('--seconds', type=float, default=20)
    args = parser.parse_args()
    if args.pid <= 0 or not 1 <= args.seconds <= 60:
        parser.error('Use a positive PID and a sampling period between 1 and 60 seconds')
    before, _ = snapshot(args.pid)
    start = time.monotonic()
    time.sleep(args.seconds)
    after, rss = snapshot(args.pid)
    duration = time.monotonic() - start
    print(json.dumps({'pid': args.pid, 'seconds': round(duration, 2),
                      'cpu_percent_of_one_core': round(100 * (after - before) / duration, 2),
                      'rss_mb_at_end': round(rss, 2)}, indent=2))


if __name__ == '__main__':
    main()
