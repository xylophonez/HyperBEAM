#!/usr/bin/env bash
# Start HyperBEAM on HB_PORT (default 8734) without overlapping listeners.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${HB_PORT:-8734}"
PIDFILE="${ROOT}/.hyperbeam-dev-server.${PORT}.pid"
LOGFILE="${ROOT}/.hyperbeam-dev-server.${PORT}.log"
ERLANG_NODE="hbdev${PORT}@127.0.0.1"
ERLANG_COOKIE="hbdev"

usage() {
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  start       Start an interactive rebar3 shell (foreground)
  start-bg    Start rebar3 shell detached (survives terminal close)
  stop        Stop the process listening on port ${PORT}
  restart     Compile, stop, start detached, and wait until HTTP is ready
  reload      Hot-reload Erlang modules in the running node (default: hb_docs)
  status      Show whether the dev server is up
  logs        Tail the detached server log
  attach      Print how to use the running node (does not start a new one)

Environment:
  HB_PORT     HTTP port (default: 8734)

Prefer 'restart' after code changes — it compiles, replaces the listener, and
waits until http://localhost:${PORT}/docs responds. For cookbook docs work
(hb_docs.erl and related assets), use 'restart' only; 'reload' is unreliable.
Do not run bare 'rebar3 shell' on an occupied port; that boots a node without
HTTP (eaddrinuse).
EOF
}

# Only the TCP listener — not browser/client connections on the same port.
port_pids() {
  lsof -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true
}

http_ok() {
  curl -sf -m 2 -o /dev/null "http://localhost:${PORT}/docs" 2>/dev/null
}

rebar_shell_cmd() {
  printf 'env HB_PORT=%s rebar3 shell --name %s --setcookie %s' \
    "$PORT" "$ERLANG_NODE" "$ERLANG_COOKIE"
}

wait_port_free() {
  local i=0
  while [[ $i -lt 50 ]]; do
    [[ -z "$(port_pids)" ]] && return 0
    sleep 0.2
    i=$((i + 1))
  done
  echo "Port ${PORT} still in use after stop (pid(s): $(port_pids | tr '\n' ' '))" >&2
  return 1
}

wait_ready() {
  local i=0
  while [[ $i -lt 180 ]]; do
    if http_ok; then
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  echo "Server on port ${PORT} did not become ready within 90s." >&2
  echo "See log: ${LOGFILE}" >&2
  return 1
}

record_listener_pid() {
  local beam_pid
  beam_pid="$(port_pids | head -1)"
  if [[ -n "$beam_pid" ]]; then
    echo "$beam_pid" >"$PIDFILE"
  fi
}

status() {
  local pids
  pids="$(port_pids | tr '\n' ' ' | sed 's/ $//')"
  if [[ -z "$pids" ]]; then
    echo "down (nothing listening on port ${PORT})"
    return 1
  fi
  if http_ok; then
    echo "up   http://localhost:${PORT}  (listener pid(s): ${pids})"
    return 0
  fi
  echo "stale (port ${PORT} held by pid(s): ${pids}, HTTP not responding)"
  return 2
}

kill_pid_soft_then_hard() {
  local pid="$1"
  [[ -z "$pid" ]] && return 0
  kill "$pid" 2>/dev/null || true
}

stop() {
  local pids pid ppid
  pids="$(port_pids)"
  if [[ -f "$PIDFILE" ]]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]]; then
      pids="$(printf '%s\n%s' "$pids" "$pid" | sed '/^$/d' | sort -u)"
    fi
  fi
  if [[ -z "$pids" ]]; then
    rm -f "$PIDFILE"
    echo "No listener on port ${PORT}"
    return 0
  fi
  echo "Stopping listener(s) on port ${PORT}: ${pids//$'\n'/ }"
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill_pid_soft_then_hard "$pid"
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$ppid" && "$ppid" != "1" ]]; then
      kill_pid_soft_then_hard "$ppid"
    fi
  done <<<"$pids"
  sleep 0.5
  pids="$(port_pids)"
  if [[ -n "$pids" ]]; then
    echo "Force-stopping remaining listener(s): ${pids//$'\n'/ }"
    while IFS= read -r pid; do
      [[ -z "$pid" ]] && continue
      kill -9 "$pid" 2>/dev/null || true
    done <<<"$pids"
  fi
  rm -f "$PIDFILE"
  wait_port_free
}

start_foreground() {
  local existing
  existing="$(port_pids)"
  if [[ -n "$existing" ]]; then
    if http_ok; then
      echo "HyperBEAM already running at http://localhost:${PORT}"
      echo "listener pid(s): ${existing//$'\n'/ }"
      echo "Use: $(basename "$0") attach"
      echo "Or:  $(basename "$0") restart"
      exit 0
    fi
    echo "Port ${PORT} is in use but not responding — cleaning up stale listener(s)."
    stop
  fi

  cd "$ROOT"
  export HB_PORT="$PORT"
  echo "Starting HyperBEAM on http://localhost:${PORT} (foreground) ..."
  # shellcheck disable=SC2093
  exec bash -c "$(rebar_shell_cmd)"
}

start_background() {
  local existing launcher_pid
  existing="$(port_pids)"
  if [[ -n "$existing" ]]; then
    if http_ok; then
      echo "HyperBEAM already running at http://localhost:${PORT}"
      record_listener_pid
      return 0
    fi
    echo "Port ${PORT} is in use but not responding — cleaning up stale listener(s)."
    stop
  fi

  cd "$ROOT"
  export HB_PORT="$PORT"
  export ROOT PORT LOGFILE ERLANG_NODE ERLANG_COOKIE
  echo "Starting HyperBEAM on http://localhost:${PORT} (detached) ..."
  echo "Log: ${LOGFILE}"
  # rebar3 shell needs open stdin and must outlive Cursor agent shells.
  # Double-fork + setsid reparents to init; tail keeps stdin open for the VM.
  perl -e '
    use POSIX qw(setsid);
    my $root = $ENV{ROOT};
    my $port = $ENV{PORT};
    my $log = $ENV{LOGFILE};
    my $node = $ENV{ERLANG_NODE};
    my $cookie = $ENV{ERLANG_COOKIE};
    my $pid = fork();
    exit 0 if $pid;
    setsid();
    $pid = fork();
    exit 0 if $pid;
    chdir $root or die $!;
    open(STDIN, "<", "/dev/null");
    open(STDOUT, ">>", $log) or die $!;
    open(STDERR, ">&STDOUT");
    exec "sh", "-c",
      "tail -f /dev/null | exec env HB_PORT=${port} rebar3 shell --name ${node} --setcookie ${cookie}"
      or die $!;
  ' &
  launcher_pid=$!
  echo "$launcher_pid" >"$PIDFILE"
}

restart() {
  cd "$ROOT"
  export HB_PORT="$PORT"
  echo "Compiling ..."
  rebar3 compile
  stop
  start_background
  if wait_ready; then
    record_listener_pid
    echo "ready http://localhost:${PORT}"
    echo "Log: ${LOGFILE}"
  else
    exit 1
  fi
}

running_erlang_node() {
  erl -noshell -name "devprobe$$@127.0.0.1" -setcookie "$ERLANG_COOKIE" \
    -eval "
      Node = '${ERLANG_NODE}',
      case net_adm:ping(Node) of
        pong -> io:format(\"~s\", [atom_to_list(Node)]);
        _ -> halt(1)
      end,
      init:stop().
    " 2>/dev/null || true
}

reload() {
  local node mods mod
  if ! http_ok; then
    echo "Dev server is not up. Run: $(basename "$0") restart" >&2
    exit 1
  fi
  node="$(running_erlang_node)"
  if [[ -z "$node" ]]; then
    echo "Could not reach Erlang node ${ERLANG_NODE}. Run: $(basename "$0") restart" >&2
    exit 1
  fi
  mods="${*:-hb_docs}"
  echo "Hot-reloading on ${node}: ${mods}"
  for mod in $mods; do
    erl -noshell -name "devreload$$@127.0.0.1" -setcookie "$ERLANG_COOKIE" \
      -remsh "$node" \
      -eval "c:c(${mod}), io:format(\"reloaded ${mod}~n\"), init:stop()."
  done
  if http_ok; then
    echo "ready http://localhost:${PORT}"
  fi
}

attach() {
  if ! status; then
    echo "Nothing to attach to. Run: $(basename "$0") start"
    exit 1
  fi
  cat <<EOF
Dev server is already running at http://localhost:${PORT}.

Do not start another 'rebar3 shell' on the same port — that causes eaddrinuse.

After editing Erlang modules, use:
  ./scripts/dev-server.sh restart

For cookbook docs (hb_docs.erl, site.css), prefer restart only — reload is
unreliable for docs HTML/CSS.

To open a remote shell to the running node:
  erl -remsh ${ERLANG_NODE} -name dev-attach@127.0.0.1 -setcookie ${ERLANG_COOKIE}

Detached log:
  ${LOGFILE}
EOF
}

logs() {
  if [[ ! -f "$LOGFILE" ]]; then
    echo "No log yet: ${LOGFILE}" >&2
    exit 1
  fi
  tail -n 80 -f "$LOGFILE"
}

cmd="${1:-start}"
shift || true
case "$cmd" in
  start) start_foreground ;;
  start-bg) start_background; wait_ready && record_listener_pid && echo "ready http://localhost:${PORT}" ;;
  stop) stop ;;
  restart) restart ;;
  reload) reload "$@" ;;
  status) status ;;
  logs) logs ;;
  attach) attach ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
