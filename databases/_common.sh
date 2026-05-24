#!/usr/bin/env bash
# _common.sh — helpers compartilhados entre módulos de banco.
# Cada módulo importa estas funções via _DBM_DB_COMMON_LOADED.

[[ -n "${_DBM_DB_COMMON_LOADED:-}" ]] && return 0
_DBM_DB_COMMON_LOADED=1

: "${_DBM_UI_LOADED:?}"
: "${_DBM_INPUT_LOADED:?}"

# db::list_section "Título" cmd args...
# Envolve a saída de um comando SQL com header + separador.
db::list_section() {
    local title=$1; shift
    ui::info "$title"
    ui::hr
    "$@"
    ui::hr
}

# db::action "descrição" cmd args...
# Executa o comando, imprime ok/error baseado no rc.
db::action() {
    local desc=$1; shift
    if "$@"; then
        ui::ok "$desc"
    else
        ui::error "Falha: $desc"
        return 1
    fi
}
