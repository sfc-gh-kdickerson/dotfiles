#!/usr/bin/env python3
"""Hold the reverse-forward for one workspace.

sf's ControlMaster from a one-shot `ssh ... true` goes away. We keep a
long-lived `sf ws ssh --command 'sleep infinity'` so the mux stays up,
then `ssh -O forward -R` on that mux. If the holder or socket dies, we
rebuild instead of exiting.
"""

from __future__ import print_function

import glob
import json
import os
import signal
import subprocess
import sys
import time

from lock import open_and_lock, pid_alive, read_lock_pid, state_dir
from protocol import HOST_PORT, daemonize, eprint

READY_VERSION = "2"


def _ip_cache_path(workspace_id):
    return os.path.join(state_dir(), "ip-%s" % workspace_id)


def workspace_ip(workspace_id, refresh=False):
    cache = _ip_cache_path(workspace_id)
    if not refresh:
        try:
            with open(cache, "r") as fh:
                ip = fh.read().strip()
            if ip:
                return ip
        except OSError:
            pass
    proc = subprocess.run(
        ["sf", "ws", "show", workspace_id, "-o", "json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit("sf ws show %s failed: %s" % (workspace_id, proc.stderr.strip()))
    rows = json.loads(proc.stdout)
    for row in rows:
        if row.get("key") == "ip":
            ip = row.get("value")
            tmp = cache + ".tmp"
            with open(tmp, "w") as fh:
                fh.write(ip + "\n")
            os.replace(tmp, cache)
            return ip
    raise SystemExit("sf ws show %s: no ip field" % workspace_id)


def mux_sock(ip):
    matches = glob.glob(os.path.expanduser("~/.ssh/sfcli-socks/*@%s:8022" % ip))
    if not matches:
        return None
    matches.sort(key=os.path.getmtime, reverse=True)
    return matches[0]


def mux_cmd(sock, *ctl):
    return ["ssh", "-O", ctl[0], *ctl[1:], "-S", sock, "dummy"]


def apply_forward(sock, spec):
    subprocess.run(mux_cmd(sock, "cancel", "-R", spec), capture_output=True)
    proc = subprocess.run(mux_cmd(sock, "forward", "-R", spec), capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            "ssh -O forward failed: %s %s" % (proc.stdout.strip(), proc.stderr.strip())
        )


def cancel_forward(sock, spec):
    if not sock:
        return
    subprocess.run(mux_cmd(sock, "cancel", "-R", spec), capture_output=True)


def cancel_workspace(workspace_id):
    spec = "%d:127.0.0.1:%d" % (HOST_PORT, HOST_PORT)
    try:
        ip = workspace_ip(workspace_id)
    except SystemExit as exc:
        eprint(str(exc))
        return 1
    sock = mux_sock(ip)
    cancel_forward(sock, spec)
    if sock:
        eprint("cancelled %s on %s" % (spec, sock))
    return 0


def start_holder(workspace_id):
    # -n: stdin is /dev/null and must not close the session.
    return subprocess.Popen(
        [
            "sf",
            "ws",
            "ssh",
            workspace_id,
            "--options",
            "-n",
            "--command",
            "sleep infinity",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def wait_sock(ip, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = mux_sock(ip)
        if sock and os.path.exists(sock):
            return sock
        time.sleep(0.2)
    return None


def write_ready(path, spec):
    with open(path, "w") as fh:
        fh.write("%s %s\n" % (READY_VERSION, spec))


def clear_ready(path):
    try:
        os.remove(path)
    except OSError:
        pass


def stop_holder(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        proc.terminate()
    try:
        proc.wait(timeout=3)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass


def main(argv):
    workspace_id = None
    daemon = False
    cancel_only = False
    log_path = os.path.join(state_dir(), "tunnel.log")
    i = 1
    while i < len(argv):
        if argv[i] == "--workspace":
            i += 1
            workspace_id = argv[i]
        elif argv[i] == "--daemon":
            daemon = True
        elif argv[i] == "--cancel-only":
            cancel_only = True
        elif argv[i] == "--log":
            i += 1
            log_path = argv[i]
        else:
            eprint("unknown arg: %s" % argv[i])
            return 2
        i += 1
    if not workspace_id:
        eprint("usage: tunnel.py --workspace ID [--daemon|--cancel-only]")
        return 2
    if cancel_only:
        return cancel_workspace(workspace_id)

    lock_path = os.path.join(state_dir(), "tunnel-%s.lock" % workspace_id)
    if daemon:
        daemonize(log_path)

    fd = open_and_lock(lock_path)
    if fd is None:
        pid = read_lock_pid(lock_path)
        if pid_alive(pid):
            eprint("tunnel already running pid=%s" % pid)
            return 0
        eprint("tunnel lock busy and holder dead")
        return 1

    spec = "%d:127.0.0.1:%d" % (HOST_PORT, HOST_PORT)
    ready_path = os.path.join(state_dir(), "tunnel-%s.ready" % workspace_id)
    ip = workspace_ip(workspace_id)
    stopping = {"done": False}

    def _stop(signum, frame):
        stopping["done"] = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    holder = None
    sock = None
    try:
        while not stopping["done"]:
            if holder is None or holder.poll() is not None:
                eprint("starting mux holder")
                holder = start_holder(workspace_id)
            sock = wait_sock(ip, timeout=20)
            if sock is None:
                eprint("mux socket never appeared; refreshing ip")
                stop_holder(holder)
                holder = None
                clear_ready(ready_path)
                try:
                    ip = workspace_ip(workspace_id, refresh=True)
                except SystemExit as exc:
                    eprint(str(exc))
                time.sleep(1)
                continue
            try:
                apply_forward(sock, spec)
            except RuntimeError as exc:
                eprint(str(exc))
                clear_ready(ready_path)
                time.sleep(1)
                continue
            write_ready(ready_path, spec)
            eprint("forward %s on %s (holder pid=%s)" % (spec, sock, holder.pid))
            while not stopping["done"]:
                time.sleep(0.5)
                if holder.poll() is not None:
                    eprint("mux holder exited %s" % holder.returncode)
                    clear_ready(ready_path)
                    holder = None
                    break
                if not os.path.exists(sock):
                    eprint("mux socket vanished; rebuilding")
                    clear_ready(ready_path)
                    stop_holder(holder)
                    holder = None
                    break
    finally:
        clear_ready(ready_path)
        cancel_forward(sock, spec)
        stop_holder(holder)
        eprint("tunnel stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv) or 0)
