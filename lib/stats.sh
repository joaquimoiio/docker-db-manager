#!/usr/bin/env bash
# stats.sh — view de CPU/RAM/Net dos containers do dbm.

[[ -n "${_DBM_STATS_LOADED:-}" ]] && return 0
_DBM_STATS_LOADED=1

: "${_DBM_UI_LOADED:?source lib/ui.sh first}"
: "${_DBM_DOCKER_LOADED:?source lib/docker.sh first}"

# stats::view — tabela snapshot de todos os containers gerenciados
stats::view() {
    ui::titlebar "Recursos · CPU / Memória" "snapshot"
    ui::table_header "BANCO" 14 "STATUS" 14 "CPU" 9 "MEM" 14 "CONTAINER" 24
    local db name color label state pill cpumem cpu mem
    docker::_refresh_stats
    for db in "${DB_TYPES[@]}"; do
        name=$(core::db_config "$db" CONTAINER)
        label=$(core::db_config "$db" LABEL)
        color=$(db_color "$db")
        state=$(docker::state "$name")
        case "$state" in
            running) pill="${CLR_OK}${BOLD}${GLYPH_DOT} rodando${NC}"  ;;
            exited|created|paused) pill="${CLR_WARN}${BOLD}${GLYPH_SQUARE} parado${NC}" ;;
            *) pill="${DIM}${CLR_MUTED}${GLYPH_RING} ausente${NC}" ;;
        esac
        cpumem="${_DOCK_STATS_MAP[$name]:-}"
        if [[ -n "$cpumem" ]]; then
            cpu="${cpumem%%|*}"; mem="${cpumem##*|}"
        else
            cpu="—"; mem="—"
        fi
        ui::table_row \
            "${color}${BOLD}${label}${NC}" 14 \
            "$pill" 14 \
            "$cpu" 9 \
            "$mem" 14 \
            "${CLR_FG}$name${NC}" 24
    done
    printf '\n'
}
