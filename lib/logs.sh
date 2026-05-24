#!/usr/bin/env bash
# logs.sh — visualizador de logs (tail).

[[ -n "${_DBM_LOGS_LOADED:-}" ]] && return 0
_DBM_LOGS_LOADED=1

: "${_DBM_UI_LOADED:?source lib/ui.sh first}"
: "${_DBM_DOCKER_LOADED:?source lib/docker.sh first}"

# logs::tail DB [N=50]
logs::tail() {
    local db=$1 n=${2:-50}
    local name; name=$(core::db_config "$db" CONTAINER)
    if ! docker::exists "$name"; then
        ui::error "Container ${BOLD}$name${NC} não existe."
        return 1
    fi
    ui::titlebar "Logs · $name" "últimas $n linhas"
    docker logs --tail "$n" "$name" 2>&1
    printf '\n'
    ui::muted "fim do log."
}
