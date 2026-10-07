#!/usr/bin/env bash
# REACHABLE hardened CI lane — egress containment for a scan (or any) container.
#
# Creates an INTERNAL docker network (no route to the internet) plus a squid
# proxy that allowlists exactly the hosts you name. A process inside the lane
# that ignores the proxy settings FAILS to connect rather than leaking; a
# process that honours them can reach only the allowlist, and every denial is
# logged (TCP_DENIED) and printed by `down`.
#
# This is the same mechanism REACHABLE's own benchmark harness uses to contain
# coding agents (reach-vibe-lab, REACH_LANE_HARDENED).
#
# Usage (see reachable-hardened.yml for the full workflow):
#   ALLOWED_HOSTS="pypi.org files.pythonhosted.org ..." ./harden-egress.sh up
#   ./harden-egress.sh run <docker-run-args...>   # adds network + proxy env
#   ./harden-egress.sh down                        # prints denials, tears down
#
# A leading dot in a host entry means "that domain and every subdomain"
# (squid's dstdomain suffix form), e.g. ".githubusercontent.com".
set -euo pipefail

LANE_NAME="${LANE_NAME:-reach-ci-lane}"
NET="${LANE_NAME}-net"
PROXY="${LANE_NAME}-proxy"
PROXY_PORT=3128
PROXY_IMAGE="${PROXY_IMAGE:-ubuntu/squid:latest}"
STATE_DIR="${RUNNER_TEMP:-/tmp}/${LANE_NAME}"

up() {
  if [ -z "${ALLOWED_HOSTS:-}" ]; then
    echo "::error::ALLOWED_HOSTS is empty — refusing to build a proxy that can reach nothing" >&2
    exit 1
  fi
  mkdir -p "${STATE_DIR}"
  {
    echo "http_port ${PROXY_PORT}"
    for host in ${ALLOWED_HOSTS}; do
      echo "acl allowed_dst dstdomain ${host}"
    done
    echo "acl SSL_ports port 443"
    echo "acl CONNECT method CONNECT"
    echo "http_access deny CONNECT !SSL_ports"
    echo "http_access allow allowed_dst"
    echo "http_access deny all"
    # squid FATALs on /dev/stdout (it drops root before opening logs); this
    # path is owned by the squid user in the ubuntu/squid image.
    echo "access_log stdio:/var/log/squid/access.log squid"
    echo "cache deny all"
  } > "${STATE_DIR}/squid.conf"

  docker network create --internal "${NET}" >/dev/null
  docker run -d --name "${PROXY}" --network "${NET}" \
    -v "${STATE_DIR}/squid.conf:/etc/squid/squid.conf:ro" \
    "${PROXY_IMAGE}" >/dev/null
  # The proxy's second leg is the only route out; the payload container never
  # joins a routable network.
  docker network connect bridge "${PROXY}"

  # Readiness is a real TCP connect — squid's startup lines never reach
  # `docker logs`, so grepping them would wait forever on a healthy proxy.
  for _ in $(seq 1 120); do
    if docker exec "${PROXY}" bash -c "exec 3<>/dev/tcp/127.0.0.1/${PROXY_PORT}" 2>/dev/null; then
      echo "hardened lane up: network=${NET} proxy=${PROXY} ($(echo ${ALLOWED_HOSTS} | wc -w | tr -d ' ') allowed hosts)"
      return 0
    fi
    sleep 0.5
  done
  echo "::error::egress proxy never became ready; refusing to run anything open" >&2
  docker logs "${PROXY}" >&2 || true
  exit 1
}

# run <docker-run-args...>: docker run on the lane network with proxy env set.
run() {
  exec docker run --network "${NET}" \
    -e "HTTP_PROXY=http://${PROXY}:${PROXY_PORT}" \
    -e "HTTPS_PROXY=http://${PROXY}:${PROXY_PORT}" \
    -e "http_proxy=http://${PROXY}:${PROXY_PORT}" \
    -e "https_proxy=http://${PROXY}:${PROXY_PORT}" \
    -e "NO_PROXY=localhost,127.0.0.1" \
    -e "no_proxy=localhost,127.0.0.1" \
    "$@"
}

down() {
  echo "── egress denials recorded by the proxy (TCP_DENIED = blocked attempt) ──"
  docker exec "${PROXY}" sh -c 'grep TCP_DENIED /var/log/squid/access.log || echo "(none)"' 2>/dev/null || echo "(proxy already gone)"
  docker rm -f "${PROXY}" >/dev/null 2>&1 || true
  docker network rm "${NET}" >/dev/null 2>&1 || true
}

case "${1:-}" in
  up) up ;;
  run) shift; run "$@" ;;
  down) down ;;
  *) echo "usage: $0 {up|run <docker-run-args...>|down}" >&2; exit 2 ;;
esac
