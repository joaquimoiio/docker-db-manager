#!/usr/bin/env bash
# core.sh — bootstrap, paths, capacidades do terminal, traps.
# Carregado primeiro por dbm. Não depende de outros módulos do projeto
# além de theme.sh (apenas para garantir cores no banner de erro).

[[ -n "${_DBM_CORE_LOADED:-}" ]] && return 0
_DBM_CORE_LOADED=1

# ─── Paths ───────────────────────────────────────────────────────────────────
# DBM_ROOT é definido por dbm antes de sourcear; aqui derivamos fallback seguro
: "${DBM_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DBM_ROOT

DBM_LIB="$DBM_ROOT/lib"
DBM_DB_DIR="$DBM_ROOT/databases"
DBM_BACKUP_DIR="$DBM_ROOT/backups"
DBM_ETC="$DBM_ROOT/etc"

DBM_USER_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/dbm"
DBM_USER_CFG="$DBM_USER_CFG_DIR/config.sh"

# ─── Capacidades do terminal ─────────────────────────────────────────────────
core::is_tty()       { [[ -t 1 ]]; }
core::has_color()    { [[ -t 1 && "${TERM:-}" != "dumb" ]]; }
core::has_truecolor(){ [[ "${COLORTERM:-}" =~ ^(truecolor|24bit)$ ]]; }

# Tamanho do terminal: cacheado para evitar fork(tput) em cada chamada.
# Atualiza em SIGWINCH (resize) e pode ser invalidado com core::term_invalidate.
_CORE_TERM_COLS=0
_CORE_TERM_LINES=0
core::_refresh_term() {
    _CORE_TERM_COLS=${COLUMNS:-0}
    _CORE_TERM_LINES=${LINES:-0}
    if (( _CORE_TERM_COLS == 0 )) || (( _CORE_TERM_LINES == 0 )); then
        # Usa stty (geralmente mais rápido que tput em bash interativo)
        local size
        size=$(stty size 2>/dev/null) || size="24 80"
        _CORE_TERM_LINES=${size% *}
        _CORE_TERM_COLS=${size#* }
    fi
    (( _CORE_TERM_COLS > 0 )) || _CORE_TERM_COLS=80
    (( _CORE_TERM_LINES > 0 )) || _CORE_TERM_LINES=24
}
core::term_invalidate() { _CORE_TERM_COLS=0; _CORE_TERM_LINES=0; }
core::term_cols()  { (( _CORE_TERM_COLS == 0 )) && core::_refresh_term; printf '%d' "$_CORE_TERM_COLS"; }
core::term_lines() { (( _CORE_TERM_LINES == 0 )) && core::_refresh_term; printf '%d' "$_CORE_TERM_LINES"; }
trap 'core::term_invalidate' WINCH

# Animações: desligadas em pipe, em CI, ou via DBM_NO_ANIM=1
core::anim_enabled() {
    [[ "${DBM_NO_ANIM:-0}" = "1" ]] && return 1
    [[ "${CI:-}" = "true" ]] && return 1
    core::is_tty
}

# Tem comando no PATH?
core::has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ─── Controle de cursor / tela ───────────────────────────────────────────────
core::hide_cursor()  { core::anim_enabled && printf '\033[?25l'; }
core::show_cursor()  { core::anim_enabled && printf '\033[?25h'; }
core::cls()          { printf '\033[2J\033[H'; }
core::home()         { printf '\033[H'; }
core::clear_below()  { printf '\033[J'; }
core::save_cursor()  { printf '\033[s'; }
core::rest_cursor()  { printf '\033[u'; }

# Modo de tela alternativa (entra/sai como htop, lazygit)
core::altscreen_on()  { core::anim_enabled && printf '\033[?1049h'; }
core::altscreen_off() { core::anim_enabled && printf '\033[?1049l'; }

# ─── Pré-flight ──────────────────────────────────────────────────────────────
core::require_docker() {
    if ! core::has_cmd docker; then
        printf '\n  \033[38;5;203m✖\033[0m  docker não encontrado no PATH.\n\n' >&2
        exit 127
    fi
    if ! docker info >/dev/null 2>&1; then
        printf '\n  \033[38;5;203m✖\033[0m  daemon do Docker inacessível. Suba o serviço primeiro.\n\n' >&2
        exit 1
    fi
}

# ─── Trap de saída limpa ─────────────────────────────────────────────────────
# Restaura cursor e tela alternativa em qualquer saída.
core::_cleanup() {
    core::show_cursor
    core::altscreen_off
}
trap 'core::_cleanup' EXIT
trap 'core::_cleanup; exit 130' INT
trap 'core::_cleanup; exit 143' TERM

# ─── Acesso a configuração de módulos ────────────────────────────────────────
# db_config postgres PORT → echo do valor de POSTGRES_PORT
core::db_config() {
    local var="${1^^}_$2"
    printf '%s' "${!var}"
}

# ─── Helpers de arquivo ──────────────────────────────────────────────────────
core::ensure_dir() { [[ -d "$1" ]] || mkdir -p "$1"; }
