#!/usr/bin/env bash
# networks.sh — listagem/inspect de networks Docker.

[[ -n "${_DBM_NETWORKS_LOADED:-}" ]] && return 0
_DBM_NETWORKS_LOADED=1

: "${_DBM_UI_LOADED:?source lib/ui.sh first}"

networks::list() {
    ui::titlebar "Networks Docker"
    ui::table_header "DRIVER" 10 "ESCOPO" 8 "NOME" 30 "ID" 14
    local driver scope name id
    while IFS=$'\t' read -r driver scope name id; do
        [[ -z "$name" ]] && continue
        ui::table_row \
            "${CLR_INFO}$driver${NC}" 10 \
            "${CLR_MUTED}$scope${NC}" 8 \
            "${BOLD}${CLR_FG}$name${NC}" 30 \
            "${DIM}${CLR_MUTED}$id${NC}" 14
    done < <(docker network ls --format '{{.Driver}}\t{{.Scope}}\t{{.Name}}\t{{.ID}}' 2>/dev/null)
    printf '\n'
}

networks::inspect() {
    local name=$1
    if [[ -z "$name" ]]; then
        local -a nets=()
        while IFS= read -r n; do nets+=("$n"); done < <(docker network ls --format '{{.Name}}' 2>/dev/null)
        (( ${#nets[@]} == 0 )) && { ui::warn "Nenhuma network."; return; }
        input::choose "Network" "${nets[@]}" || return
        name="$REPLY_CHOICE"
    fi
    ui::titlebar "Network · $name"
    docker network inspect "$name" 2>&1 | (core::has_cmd jq && jq '.' || cat)
}
