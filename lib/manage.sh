#!/usr/bin/env bash
# manage.sh — menu de operações de banco (listar/criar/excluir bancos e
# usuários, restaurar backup). Single-key, atalhos por letra.

[[ -n "${_DBM_MANAGE_LOADED:-}" ]] && return 0
_DBM_MANAGE_LOADED=1

: "${_DBM_UI_LOADED:?}"
: "${_DBM_DOCKER_LOADED:?}"
: "${_DBM_INPUT_LOADED:?}"

manage::_render() {
    local db=$1 name=$2
    ui::db_header "$db" "gerenciar bancos · usuários · backups"

    printf '  %sstatus do container:%s ' "$DIM$CLR_MUTED" "$NC"
    ui::status_pill "$name"; printf '\n'

    type "${db}_manage_note" &>/dev/null && { printf '\n'; "${db}_manage_note"; }

    ui::section "Bancos de dados"
    printf '    %s%s[d]%s %slistar%s        %s%s[c]%s %scriar%s        %s%s[D]%s %sexcluir%s\n' \
        "$BOLD$CLR_OK" "" "$NC" "$CLR_FG" "$NC" \
        "$BOLD$CLR_OK" "" "$NC" "$CLR_FG" "$NC" \
        "$BOLD$CLR_ERR" "" "$NC" "$CLR_FG" "$NC"

    ui::section "Usuários"
    printf '    %s%s[u]%s %slistar%s        %s%s[n]%s %scriar%s        %s%s[U]%s %sexcluir%s\n' \
        "$BOLD$CLR_OK" "" "$NC" "$CLR_FG" "$NC" \
        "$BOLD$CLR_OK" "" "$NC" "$CLR_FG" "$NC" \
        "$BOLD$CLR_ERR" "" "$NC" "$CLR_FG" "$NC"

    ui::section "Restauração"
    printf '    %s%s[r]%s %srestaurar de backup%s   %s%s(backups/%s/)%s\n' \
        "$BOLD$CLR_ACCENT" "" "$NC" "$CLR_FG" "$NC" \
        "$DIM$CLR_MUTED" "" "$db" "$NC"

    ui::keybar "q" "voltar"
}

manage::menu() {
    local db=$1
    local name; name=$(core::db_config "$db" CONTAINER)

    if ! docker::running "$name"; then
        core::cls
        ui::db_header "$db" "gerenciar"
        ui::error "Container ${BOLD}$name${NC} não está rodando."
        ui::muted "Inicie com 's' no dashboard."
        ui::pause
        return
    fi

    while true; do
        core::cls
        manage::_render "$db" "$name"
        input::read_key
        local k=$REPLY_KEY
        printf '\n'
        case "$k" in
            d) "${db}_list_databases"  ; ui::pause ;;
            c) "${db}_create_database" ; ui::pause ;;
            D) "${db}_drop_database"   ; ui::pause ;;
            u) "${db}_list_users"      ; ui::pause ;;
            n) "${db}_create_user"     ; ui::pause ;;
            U) "${db}_drop_user"       ; ui::pause ;;
            r) "${db}_restore"         ; ui::pause ;;
            q|Q|ESC) return ;;
            *) ;;
        esac
    done
}
