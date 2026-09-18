"""Exclusive flock helpers. The OS drops the lock when the holder dies."""

from __future__ import print_function

import fcntl
import os
import sys

LOCK_DIR_MODE = 0o700
LOCK_FILE_MODE = 0o600


def state_dir():
    path = os.path.join(os.path.expanduser("~"), ".local", "share", "cws-host-mcp")
    os.makedirs(path, mode=LOCK_DIR_MODE, exist_ok=True)
    return path


def open_and_lock(path, nonblocking=True):
    """Acquire LOCK_EX on path and write this pid into the file.

    Returns an open fd that must be kept alive for the process lifetime.
    Returns None if another process already holds the lock.
    """
    os.makedirs(os.path.dirname(path), mode=LOCK_DIR_MODE, exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT, LOCK_FILE_MODE)
    flags = fcntl.LOCK_EX
    if nonblocking:
        flags |= fcntl.LOCK_NB
    try:
        fcntl.flock(fd, flags)
    except (BlockingIOError, OSError):
        os.close(fd)
        return None
    os.lseek(fd, 0, os.SEEK_SET)
    os.ftruncate(fd, 0)
    os.write(fd, ("%d\n" % os.getpid()).encode("ascii"))
    os.fsync(fd)
    return fd


def read_lock_pid(path):
    try:
        with open(path, "r") as fh:
            line = fh.read().strip().split()[0]
        return int(line)
    except (OSError, ValueError, IndexError):
        return None


def pid_alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def hold_or_exit(path, already_running_ok=True):
    """Lock or exit. Keeps the fd in a global so GC cannot close it."""
    fd = open_and_lock(path)
    if fd is None:
        pid = read_lock_pid(path)
        if already_running_ok and pid_alive(pid):
            print("already running pid=%s" % pid, file=sys.stderr)
            sys.exit(0)
        print("lock busy and holder is not alive: %s" % path, file=sys.stderr)
        sys.exit(1)
    # Leak on purpose — process lifetime.
    globals().setdefault("_HELD_LOCK_FDS", []).append(fd)
    return fd
