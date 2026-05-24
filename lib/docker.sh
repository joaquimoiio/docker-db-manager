#!/usr/bin/env bash
# docker.sh — wrappers genéricos sobre o CLI do docker.
# Centraliza chamadas a `docker ps`, `docker stats`, etc. para permitir
# cache curto (evita N invocações em redraws de dashboard).

[[ -n "${_DBM_DOCKER_LOADED:-}" ]] && return 0
_DBM_DOCKER_LOADED=1

: "${_DBM_CORE_LOADED:?source lib/core.sh first}"

# ─── Cache de `docker ps -a` ─────────────────────────────────────────────────
_DOCK_PS_TS=0
_DOCK_PS_DATA=""
_DOCK_CACHE_TTL=${DBM_CACHE_TTL:-2}

# Formato: NAME|STATE|STATUS|PORTS
docker::ps_cached() {
    local now; now=$(date +%s)
    if (( now - _DOCK_PS_TS >= _DOCK_CACHE_TTL )); then
        _DOCK_PS_DATA=$(docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.Ports}}' 2>/dev/null || true)
        _DOCK_PS_TS=$now
    fi
    printf '%s' "$_DOCK_PS_DATA"
}

docker::ps_invalidate() { _DOCK_PS_TS=0; }

# ─── Estado de containers ────────────────────────────────────────────────────
# docker::state NAME → "running" | "exited" | "created" | "paused" | "absent"
docker::state() {
    local name=$1 line
    line=$(docker::ps_cached | awk -F'|' -v n="$name" '$1==n {print $2; exit}')
    [[ -z "$line" ]] && { printf 'absent'; return; }
    printf '%s' "$line"
}

docker::exists()  { [[ "$(docker::state "$1")" != "absent" ]]; }
docker::running() { [[ "$(docker::state "$1")" == "running" ]]; }

# Aliases retrocompat
container_exists()  { docker::exists  "$1"; }
container_running() { docker::running "$1"; }

# ─── Stats (CPU/MEM) ─────────────────────────────────────────────────────────
# docker::stats NAME → "CPU%|MEM" (vazio se não rodando)
# Cacheia em batch a cada TTL — uma chamada cobre todos os containers.
_DOCK_STATS_TS=0
declare -gA _DOCK_STATS_MAP=()

docker::_refresh_stats() {
    local now; now=$(date +%s)
    (( now - _DOCK_STATS_TS < _DOCK_CACHE_TTL )) && return
    _DOCK_STATS_TS=$now
    _DOCK_STATS_MAP=()
    local raw line name cpu mem
    raw=$(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/dev/null || true)
    while IFS='|' read -r name cpu mem; do
        [[ -z "$name" ]] && continue
        # mem vem como "180MiB / 1.94GiB" — pegamos só o lado esquerdo
        local memshort="${mem%% / *}"
        _DOCK_STATS_MAP[$name]="${cpu}|${memshort}"
    done <<<"$raw"
}

docker::stats() {
    docker::_refresh_stats
    printf '%s' "${_DOCK_STATS_MAP[$1]:-}"
}

# ─── Helpers de portas ───────────────────────────────────────────────────────
# Detecta se uma porta TCP no host está ocupada por OUTRO processo
docker::port_in_use() {
    local port=$1
    (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | awk '{print $4}' | grep -qE "[:.]${port}$"
}
