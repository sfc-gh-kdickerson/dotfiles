#!/usr/bin/env python3
"""Hold the reverse-forward for one workspace.

sf's ControlMaster from a one-shot `ssh ... true` goes away. We keep a
long-lived `sf ws ssh --command 'sleep infinity'` so the mux stays up,
then `ssh -O forward -R` on that mux. If the holder or socket dies, we
rebuild instead of exiting.

The holder runs its own ControlMaster instead of sf's shared one. Cursor's
Remote-SSH sessions pile up on the shared master until sshd's MaxSessions
refuses new ones, and then nothing can run a command over it.

sf's ssh config also reverse-forwards the dev-daemon and ssh-agent sockets.
Every other ssh session to the workspace rebinds those paths and leaves them
dead when it exits, so the holder probes them and forwards them again on its
own mux whenever they stop answering.
"""

from __future__ import print_function

import glob
import json
import os
import shlex
import signal
import subprocess
import sys
import time

from lock import open_and_lock, pid_alive, read_lock_pid, state_dir
from protocol import HOST_PORT, daemonize, eprint, read_token

READY_VERSION = "3"
SOCKET_CHECK_EVERY = 10

# Connect to each path; unlink and print the ones that refuse so they can be bound again.
DEAD_SOCKETS = r"""python3 -c '
import os, socket, sys
for p in sys.argv[1:]:
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(2)
    try:
        s.connect(p)
    except OSError:
        try:
            os.unlink(p)
        except OSError:
            pass
        print(p)
    finally:
        s.close()
'"""


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
    try:
        proc = subprocess.run(
            ["sf", "ws", "show", workspace_id, "-o", "json"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        raise SystemExit("sf ws show %s timed out" % workspace_id)
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


def mux_socks(ip):
    matches = glob.glob(os.path.expanduser("~/.ssh/sfcli-socks/*@%s:8022" % ip))
    dated = []
    for path in matches:
        try:
            dated.append((os.path.getmtime(path), path))
        except OSError:
            continue
    dated.sort(reverse=True)
    return [path for _mtime, path in dated]


def mux_sock(ip):
    matches = mux_socks(ip)
    return matches[0] if matches else None


def mux_cmd(sock, *ctl):
    return ["ssh", "-O", ctl[0], *ctl[1:], "-S", sock, "dummy"]


def mux_alive(sock):
    if not sock or not os.path.exists(sock):
        return False
    try:
        proc = subprocess.run(mux_cmd(sock, "check"), capture_output=True, timeout=2)
    except subprocess.TimeoutExpired:
        return False
    return proc.returncode == 0


def drop_mux(sock):
    """Kill a ControlMaster and remove a stale socket so the next holder is clean."""
    if not sock:
        return
    try:
        subprocess.run(mux_cmd(sock, "exit"), capture_output=True, timeout=2)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.unlink(sock)
    except OSError:
        pass


def mux_exec(sock, remote, timeout=6):
    try:
        return subprocess.run(
            [
                "ssh",
                "-S",
                sock,
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=3",
                "dummy",
                remote,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None


def remote_host_ok(sock, token):
    """True when CWS:HOST_PORT already reaches the Mac host through this mux."""
    if not sock or not token:
        return False
    remote = "curl -fsS -m 2 -H %s http://127.0.0.1:%d/health" % (
        shlex.quote("Authorization: Bearer %s" % token),
        HOST_PORT,
    )
    proc = mux_exec(sock, remote)
    if proc is None or proc.returncode != 0:
        return False
    return '"ok"' in (proc.stdout or "")


def apply_forward(sock, spec, token=None):
    # If this mux already owns the reverse forward, a second -R fails with
    # "listen port 18766". Cancelling it then racing a rebind is how connect
    # used to spend minutes failing. Probe first; only cancel a dead bind.
    if token and remote_host_ok(sock, token):
        return
    try:
        proc = subprocess.run(
            mux_cmd(sock, "forward", "-R", spec), capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("ssh -O forward timed out")
    if proc.returncode == 0:
        return
    if token and remote_host_ok(sock, token):
        eprint("forward already up (listen port busy); leaving it")
        return
    cancel_forward(sock, spec)
    time.sleep(1)
    try:
        proc = subprocess.run(
            mux_cmd(sock, "forward", "-R", spec), capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("ssh -O forward timed out")
    if proc.returncode == 0:
        return
    if token and remote_host_ok(sock, token):
        eprint("forward already up after rebind attempt; leaving it")
        return
    raise RuntimeError(
        "ssh -O forward failed: %s %s" % (proc.stdout.strip(), proc.stderr.strip())
    )


def cancel_forward(sock, spec):
    if not sock:
        return
    try:
        subprocess.run(mux_cmd(sock, "cancel", "-R", spec), capture_output=True, timeout=2)
    except subprocess.TimeoutExpired:
        pass


def local_agent_sock():
    path = os.environ.get("SSH_AUTH_SOCK")
    if not path:
        try:
            path = subprocess.run(
                ["launchctl", "getenv", "SSH_AUTH_SOCK"], capture_output=True, text=True, timeout=2
            ).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            path = ""
    return path or None


_remote_users = {}


def remote_user(sock):
    if sock not in _remote_users:
        proc = mux_exec(sock, "id -un")
        if proc is None or proc.returncode != 0 or not proc.stdout.strip():
            return None
        _remote_users[sock] = proc.stdout.strip()
    return _remote_users[sock]


def socket_forwards(sock):
    """Remote:local unix socket specs sf's ssh config forwards, for the user on this mux."""
    user = remote_user(sock)
    if not user:
        return []
    pairs = [
        ("/dev/shm/dev-daemon.sock", os.path.expanduser("~/.cache/sfcli/dev-daemon.sock")),
        ("/dev/shm/ssh-agent-%s.sock" % user, local_agent_sock()),
    ]
    return [(remote, local) for remote, local in pairs if local and os.path.exists(local)]


def heal_sockets(sock):
    forwards = socket_forwards(sock)
    if not forwards:
        return
    proc = mux_exec(sock, "%s %s" % (DEAD_SOCKETS, " ".join(shlex.quote(r) for r, _l in forwards)))
    if proc is None or proc.returncode != 0:
        return
    dead = set(proc.stdout.split())
    for remote, local in forwards:
        if remote not in dead:
            continue
        spec = "%s:%s" % (remote, local)
        cancel_forward(sock, spec)
        try:
            fwd = subprocess.run(
                mux_cmd(sock, "forward", "-R", spec), capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            eprint("socket forward %s timed out" % remote)
            continue
        if fwd.returncode == 0:
            eprint("socket forward %s was dead; forwarded it again" % remote)
        else:
            eprint("socket forward %s failed: %s" % (remote, fwd.stderr.strip()))


def _socks_for_workspace(workspace_id):
    try:
        ip = workspace_ip(workspace_id)
    except SystemExit as exc:
        eprint(str(exc))
        return None
    return mux_socks(ip)


def cancel_workspace(workspace_id):
    spec = "%d:127.0.0.1:%d" % (HOST_PORT, HOST_PORT)
    socks = _socks_for_workspace(workspace_id)
    if socks is None:
        return 1
    for sock in socks:
        cancel_forward(sock, spec)
        eprint("cancelled %s on %s" % (spec, sock))
    return 0


def drop_workspace_muxes(ip, spec):
    for sock in mux_socks(ip):
        cancel_forward(sock, spec)
        drop_mux(sock)
        eprint("tore down mux %s" % sock)


def teardown_workspace(workspace_id):
    spec = "%d:127.0.0.1:%d" % (HOST_PORT, HOST_PORT)
    clear_ready(os.path.join(state_dir(), "tunnel-%s.ready" % workspace_id))
    drop_mux(own_sock(workspace_id))
    try:
        ip = workspace_ip(workspace_id)
    except SystemExit as exc:
        eprint(str(exc))
        return 1
    drop_workspace_muxes(ip, spec)
    return 0


def own_sock(workspace_id):
    return os.path.expanduser("~/.ssh/sfcli-socks/cws-link-%s" % workspace_id)


def start_holder(workspace_id):
    # -n: stdin is /dev/null and must not close the session.
    # The holder is the master for its own socket and takes the mux down with it.
    sock = own_sock(workspace_id)
    if not mux_alive(sock):
        drop_mux(sock)
    return subprocess.Popen(
        [
            "sf",
            "ws",
            "ssh",
            workspace_id,
            "--options",
            "-n -o ControlMaster=yes -o ControlPersist=no -o ControlPath=%s" % sock,
            "--command",
            "sleep infinity",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def wait_sock(sock, timeout=12, should_stop=None):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if should_stop and should_stop():
            return None
        if mux_alive(sock):
            return sock
        time.sleep(0.2)
    return None


def write_ready(path, spec):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("%s %s %s\n" % (READY_VERSION, os.getpid(), spec))
        # Older connect() grepped '^2 ' and recycled the daemon on miss.
        fh.write("2 %s %s\n" % (os.getpid(), spec))
    os.replace(tmp, path)


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
    teardown = False
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
        elif argv[i] == "--teardown":
            teardown = True
        elif argv[i] == "--log":
            i += 1
            log_path = argv[i]
        else:
            eprint("unknown arg: %s" % argv[i])
            return 2
        i += 1
    if not workspace_id:
        eprint("usage: tunnel.py --workspace ID [--daemon|--cancel-only|--teardown]")
        return 2
    if teardown:
        return teardown_workspace(workspace_id)
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
    clear_ready(ready_path)
    token = read_token()
    ip = workspace_ip(workspace_id)
    stopping = {"done": False}

    def _stop(signum, frame):
        stopping["done"] = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    holder = None
    sock = None
    miss_sleep = 1
    fail_sleep = 1
    last_ip_refresh = 0
    try:
        while not stopping["done"]:
            if holder is None or holder.poll() is not None:
                if holder is not None and holder.poll() is not None:
                    eprint("mux holder exited %s" % holder.returncode)
                eprint("starting mux holder")
                holder = start_holder(workspace_id)
            sock = wait_sock(own_sock(workspace_id), timeout=12, should_stop=lambda: stopping["done"])
            if sock is None:
                if stopping["done"]:
                    break
                eprint("mux socket never appeared")
                stop_holder(holder)
                holder = None
                clear_ready(ready_path)
                now = time.time()
                if now - last_ip_refresh > 60:
                    eprint("refreshing ip")
                    last_ip_refresh = now
                    try:
                        ip = workspace_ip(workspace_id, refresh=True)
                    except SystemExit as exc:
                        eprint(str(exc))
                time.sleep(miss_sleep)
                miss_sleep = min(miss_sleep * 2, 30)
                continue
            miss_sleep = 1
            if remote_host_ok(sock, token):
                write_ready(ready_path, spec)
            else:
                try:
                    apply_forward(sock, spec, token)
                except RuntimeError as exc:
                    eprint(str(exc))
                    clear_ready(ready_path)
                    time.sleep(fail_sleep)
                    fail_sleep = min(fail_sleep * 2, 15)
                    continue
                write_ready(ready_path, spec)
                eprint("forward %s on %s (holder pid=%s)" % (spec, sock, holder.pid))
            fail_sleep = 1
            misses = 0
            heal_sockets(sock)
            ticks = 0
            while not stopping["done"]:
                time.sleep(1)
                ticks += 1
                if ticks % SOCKET_CHECK_EVERY == 0:
                    heal_sockets(sock)
                    if not remote_host_ok(sock, token):
                        try:
                            apply_forward(sock, spec, token)
                            eprint("forward %s was down; forwarded it again" % spec)
                        except RuntimeError as exc:
                            eprint(str(exc))
                if holder.poll() is not None:
                    eprint("mux holder exited %s" % holder.returncode)
                    holder = None
                    clear_ready(ready_path)
                    break
                if mux_alive(sock):
                    misses = 0
                    continue
                misses += 1
                if misses < 3:
                    continue
                eprint("mux check failed; retrying forward without killing mux")
                clear_ready(ready_path)
                break
    finally:
        clear_ready(ready_path)
        cancel_forward(sock, spec)
        stop_holder(holder)
        eprint("tunnel stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv) or 0)
