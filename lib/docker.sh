#!/usr/bin/env bash
# docker.sh — wrappers genéricos sobre o CLI do docker.
# Centraliza chamadas a `docker ps`, `docker stats`, etc. para permitir
# cache curto (evita N invocações em redraws de dashboard).

[[ -n "${_DBM_DOCKER_LOADED:-}" ]] && return 0
_DBM_DOCKER_LOADED=1

: "${_DBM_CORE_LOADED:?source lib/core.sh first}"

# ─── Cache de `docker ps -a` ─────────────────────────────────────────────────
# ps é rápido (<200ms) — TTL curto. stats é lento (1-2s) — TTL bem maior, com
# refresh assíncrono para não bloquear a UI.
_DOCK_PS_TS=0
_DOCK_PS_DATA=""
_DOCK_PS_TTL=${DBM_PS_TTL:-${DBM_CACHE_TTL:-2}}
_DOCK_STATS_TTL=${DBM_STATS_TTL:-8}

# Formato: NAME|STATE|STATUS|PORTS
docker::ps_cached() {
    local now; now=$(date +%s)
    if (( now - _DOCK_PS_TS >= _DOCK_PS_TTL )); then
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
# docker stats --no-stream é lento (~1-2s). Para não travar a UI a cada redraw,
# disparamos a coleta em background; o próximo redraw consome o resultado.
# DBM_NO_STATS=1 desliga a coleta (CPU/MEM aparecem como "—").
_DOCK_STATS_TS=0
_DOCK_STATS_PID=0
_DOCK_STATS_FILE="${TMPDIR:-/tmp}/dbm-stats-$$"
declare -gA _DOCK_STATS_MAP=()

docker::_stats_ingest() {
    [[ -s "$_DOCK_STATS_FILE" ]] || return 0
    _DOCK_STATS_MAP=()
    local name cpu mem memshort
    while IFS='|' read -r name cpu mem; do
        [[ -z "$name" ]] && continue
        memshort="${mem%% / *}"
        _DOCK_STATS_MAP[$name]="${cpu}|${memshort}"
    done < "$_DOCK_STATS_FILE"
}

docker::_refresh_stats() {
    [[ "${DBM_NO_STATS:-0}" = "1" ]] && return
    local now; now=$(date +%s)

    # Background terminou? Recolhe o arquivo.
    if (( _DOCK_STATS_PID > 0 )) && ! kill -0 "$_DOCK_STATS_PID" 2>/dev/null; then
        docker::_stats_ingest
        _DOCK_STATS_PID=0
    fi

    # TTL ainda válido ou já tem job rodando? Não dispara outro.
    (( now - _DOCK_STATS_TS < _DOCK_STATS_TTL )) && return
    (( _DOCK_STATS_PID > 0 )) && return

    _DOCK_STATS_TS=$now
    ( docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' \
        >"$_DOCK_STATS_FILE" 2>/dev/null ) &
    _DOCK_STATS_PID=$!
}

# Limpeza do arquivo temporário
docker::_cleanup() {
    [[ -f "$_DOCK_STATS_FILE" ]] && rm -f "$_DOCK_STATS_FILE"
    (( _DOCK_STATS_PID > 0 )) && kill -0 "$_DOCK_STATS_PID" 2>/dev/null && kill "$_DOCK_STATS_PID" 2>/dev/null
}
trap 'docker::_cleanup' EXIT

# ─── Contexto do CLI (default vs desktop-linux etc) ──────────────────────────
# O CLI do docker pode falar com daemons diferentes (engine systemd, Docker
# Desktop, hosts remotos). Aqui expomos consulta/troca + invalidação de caches.
_DOCK_CTX_CACHED=""

docker::context_current() {
    [[ -z "$_DOCK_CTX_CACHED" ]] && _DOCK_CTX_CACHED=$(docker context show 2>/dev/null)
    printf '%s' "$_DOCK_CTX_CACHED"
}

# Lista nomes de contextos (um por linha)
docker::context_list() {
    docker context ls --format '{{.Name}}' 2>/dev/null
}

# Linha descritiva pra UI: "name → endpoint"
docker::context_describe() {
    local name=$1
    docker context inspect "$name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null
}

# Troca o contexto e invalida todos os caches dependentes do daemon
docker::context_use() {
    local name=$1
    docker context use "$name" >/dev/null 2>&1 || return 1
    _DOCK_CTX_CACHED="$name"
    docker::ps_invalidate
    _DOCK_STATS_TS=0
    _DOCK_STATS_MAP=()
    return 0
}

# ─── Helpers de portas ───────────────────────────────────────────────────────
# Detecta se uma porta TCP no host está ocupada por OUTRO processo
docker::port_in_use() {
    local port=$1
    (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | awk '{print $4}' | grep -qE "[:.]${port}$"
}
