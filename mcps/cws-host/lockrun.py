#!/usr/bin/env python3
"""Acquire an exclusive flock, write pid, exec the remaining argv.

Used for the reverse-tunnel SSH so a second connect to the same workspace
id cannot start a second -N session. The exec'd process inherits the lock fd.
"""

from __future__ import print_function

import os
import sys

from lock import open_and_lock, pid_alive, read_lock_pid


def main(argv):
    if len(argv) < 4 or argv[1] != "--lock":
        sys.stderr.write("usage: lockrun.py --lock PATH -- command [args...]\n")
        return 2
    lock_path = argv[2]
    rest = argv[3:]
    if rest and rest[0] == "--":
        rest = rest[1:]
    if not rest:
        sys.stderr.write("lockrun.py: missing command\n")
        return 2

    fd = open_and_lock(lock_path)
    if fd is None:
        pid = read_lock_pid(lock_path)
        if pid_alive(pid):
            sys.stderr.write("already running pid=%s\n" % pid)
            return 0
        sys.stderr.write("lock busy (%s) and holder pid=%s is dead\n" % (lock_path, pid))
        return 1

    # Keep fd across exec so the child holds the lock.
    os.set_inheritable(fd, True)
    os.execvp(rest[0], rest)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
