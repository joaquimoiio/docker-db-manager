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
# Tenta subir o daemon do Docker conforme o SO e o contexto ativo do CLI.
# Retorna 0 se disparou o start (não garante que o daemon já respondeu).
# Ecoa em DBM_STARTED_LABEL um rótulo amigável do que foi iniciado.
core::_start_docker_daemon() {
    local ctx; ctx=$(docker context show 2>/dev/null)
    DBM_STARTED_LABEL=""
    case "$(uname -s)" in
        Linux)
            # Contexto do Docker Desktop → unit systemd --user (sem sudo)
            if [[ "$ctx" == "desktop-linux" ]]; then
                if core::has_cmd systemctl \
                    && systemctl --user list-unit-files docker-desktop.service >/dev/null 2>&1; then
                    DBM_STARTED_LABEL="Docker Desktop"
                    systemctl --user start docker-desktop && return 0
                fi
                return 1
            fi
            # Engine systemd padrão → precisa sudo (regra em /etc/sudoers.d/dbm-docker)
            if core::has_cmd systemctl; then
                DBM_STARTED_LABEL="Docker Engine"
                sudo systemctl start docker && return 0
            elif core::has_cmd service; then
                DBM_STARTED_LABEL="Docker Engine"
                sudo service docker start && return 0
            fi
            ;;
        Darwin)
            if core::has_cmd open; then
                DBM_STARTED_LABEL="Docker Desktop"
                open --background -a Docker && return 0
            fi
            ;;
    esac
    return 1
}

# Tenta achar outro contexto cujo daemon responda. Útil quando o CLI aponta
# pro socket do Docker Desktop (parado) mas o engine systemd está OK.
# Em caso de sucesso: ecoa o nome do contexto e retorna 0.
core::_find_working_context() {
    local current other
    current=$(docker context show 2>/dev/null)
    while IFS= read -r other; do
        [[ -z "$other" || "$other" == "$current" ]] && continue
        if DOCKER_CONTEXT="$other" docker info >/dev/null 2>&1; then
            printf '%s' "$other"
            return 0
        fi
    done < <(docker context ls --format '{{.Name}}' 2>/dev/null)
    return 1
}

# Aguarda o daemon do contexto atual ficar disponível com spinner animado.
# $1 = label amigável (ex: "Docker Desktop"); $2 = timeout em segundos (opcional).
# Retorna 0 se o daemon respondeu, 1 se esgotou o tempo.
core::_wait_docker_ready() {
    local label=${1:-"Docker"} timeout=${2:-60}
    local total=$(( timeout * 2 )) i frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    for ((i=0; i<total; i++)); do
        if docker info >/dev/null 2>&1; then
            printf '\r  \033[38;5;120m✓\033[0m  %s pronto.                                    \n\n' "$label" >&2
            return 0
        fi
        printf '\r  \033[38;5;179m%s\033[0m  aguardando %s ficar pronto (%ds/%ds)...   ' \
            "${frames[i % 10]}" "$label" "$((i / 2))" "$timeout" >&2
        sleep 0.5
    done
    printf '\n\n  \033[38;5;203m✖\033[0m  %s não respondeu em %ds.\n      Tente: docker info\n\n' "$label" "$timeout" >&2
    return 1
}

# Tenta iniciar o daemon do contexto atual e aguarda responder.
# Retorna 0 se o daemon ficou disponível, 1 caso contrário.
# Não chama exit — o chamador decide o que fazer.
core::start_docker_for_context() {
    printf '\n  \033[38;5;179m⟳\033[0m  daemon do Docker inacessível — tentando iniciar...\n' >&2
    if ! core::_start_docker_daemon 2>/dev/null; then
        return 1
    fi
    local label="${DBM_STARTED_LABEL:-Docker}"
    printf '  \033[38;5;245miniciando: %s\033[0m\n' "$label" >&2
    local timeout=60
    [[ "$label" == "Docker Desktop" ]] && timeout=90
    core::_wait_docker_ready "$label" "$timeout"
}

core::require_docker() {
    if ! core::has_cmd docker; then
        printf '\n  \033[38;5;203m✖\033[0m  docker não encontrado no PATH.\n\n' >&2
        exit 127
    fi
    if docker info >/dev/null 2>&1; then
        return 0
    fi

    # Daemon não responde. Tenta iniciar antes de sugerir troca de contexto.
    if core::start_docker_for_context; then
        return 0
    fi

    # Não conseguiu iniciar o daemon do contexto atual.
    # Verifica se outro contexto já está respondendo (ex: engine enquanto Desktop está parado).
    local alt
    if alt=$(core::_find_working_context); then
        local cur; cur=$(docker context show 2>/dev/null)
        printf '\n  \033[38;5;179m⚠\033[0m  contexto ativo "%s" não responde, mas "%s" sim.\n' "$cur" "$alt" >&2
        printf '      Troque com:  \033[1mdocker context use %s\033[0m\n' "$alt" >&2
        printf '      ou rode o dashboard e tecle \033[1mc\033[0m para escolher.\n\n' >&2
        exit 1
    fi

    printf '\n  \033[38;5;203m✖\033[0m  Não foi possível iniciar o serviço do Docker. Suba manualmente e tente de novo.\n\n' >&2
    exit 1
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

# ─── Arquitetura do host / compatibilidade de imagem ─────────────────────────
# core::host_arch → "arm64" | "amd64" | "" (desconhecida)
core::host_arch() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64' ;;
        x86_64|amd64)  printf 'amd64' ;;
        *)             printf '' ;;
    esac
}

# core::db_runs_here <db> → rc 0 se a imagem do banco tem build nativo para a
# arquitetura atual. Cada módulo declara <DB>_ARCHS (default: amd64 arm64).
core::db_runs_here() {
    local db=$1 arch; arch=$(core::host_arch)
    [[ -z "$arch" ]] && return 0
    local var="${db^^}_ARCHS"
    local archs="${!var:-amd64 arm64}"
    [[ " $archs " == *" $arch "* ]]
}

# ─── Helpers de arquivo ──────────────────────────────────────────────────────
core::ensure_dir() { [[ -d "$1" ]] || mkdir -p "$1"; }
