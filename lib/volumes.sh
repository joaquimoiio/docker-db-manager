#!/usr/bin/env bash
# volumes.sh — listagem/inspect/prune de volumes Docker.

[[ -n "${_DBM_VOLUMES_LOADED:-}" ]] && return 0
_DBM_VOLUMES_LOADED=1

: "${_DBM_UI_LOADED:?source lib/ui.sh first}"

volumes::list() {
    ui::titlebar "Volumes Docker"
    ui::table_header "DRIVER" 10 "NOME" 50 "MONTAGEM" 30
    local line driver name mountpoint
    while IFS=$'\t' read -r driver name mountpoint; do
        [[ -z "$name" ]] && continue
        ui::table_row \
            "${CLR_INFO}$driver${NC}" 10 \
            "${BOLD}${CLR_FG}$name${NC}" 50 \
            "${DIM}${CLR_MUTED}$mountpoint${NC}" 30
    done < <(docker volume ls --format '{{.Driver}}\t{{.Name}}\t{{.Mountpoint}}' 2>/dev/null)
    printf '\n'
}

volumes::inspect() {
    local name=$1
    if [[ -z "$name" ]]; then
        local -a vols=()
        while IFS= read -r v; do vols+=("$v"); done < <(docker volume ls --format '{{.Name}}' 2>/dev/null)
        (( ${#vols[@]} == 0 )) && { ui::warn "Nenhum volume encontrado."; return; }
        input::choose "Volume" "${vols[@]}" || return
        name="$REPLY_CHOICE"
    fi
    ui::titlebar "Volume · $name"
    docker volume inspect "$name" 2>&1 | (core::has_cmd jq && jq '.' || cat)
}

volumes::prune() {
    ui::danger_box "Prune de volumes não utilizados" \
        "Remove TODOS os volumes que não estão em uso por nenhum container." \
        "${DIM}${CLR_MUTED}Útil para liberar espaço; cuidado se houver dados não montados.${NC}"
    if ! input::confirm_destructive "PRUNE"; then
        ui::info "Cancelado."
        return
    fi
    ui::spinner_run "executando prune" docker volume prune -f
    ui::ok "Volumes órfãos removidos."
}
