#!/usr/bin/env bash
# input.sh — coleta de input do usuário. Toda interação passa por aqui.
# Detecta fzf opcionalmente para melhor UX de seleção.

[[ -n "${_DBM_INPUT_LOADED:-}" ]] && return 0
_DBM_INPUT_LOADED=1

: "${_DBM_THEME_LOADED:?source lib/theme.sh first}"
: "${_DBM_CORE_LOADED:?source lib/core.sh first}"
: "${_DBM_UI_LOADED:?source lib/ui.sh first}"

# ─── Detecção de helpers opcionais ───────────────────────────────────────────
input::has_fzf() { core::has_cmd fzf; }
input::has_gum() { core::has_cmd gum; }

# ─── read_key: captura UMA tecla sem precisar de Enter ───────────────────────
# Retorna a tecla em REPLY_KEY. Trata sequências ESC (setas) como "UP/DOWN/LEFT/RIGHT".
input::read_key() {
    REPLY_KEY=""
    local k1 k2 k3
    IFS= read -rsn1 k1
    if [[ "$k1" == $'\x1b' ]]; then
        # Pode ser ESC sozinho ou início de seq de seta. Timeout curto.
        IFS= read -rsn1 -t 0.0005 k2 || { REPLY_KEY="ESC"; return; }
        if [[ "$k2" == "[" ]]; then
            IFS= read -rsn1 -t 0.0005 k3
            case "$k3" in
                A) REPLY_KEY="UP"    ;;
                B) REPLY_KEY="DOWN"  ;;
                C) REPLY_KEY="RIGHT" ;;
                D) REPLY_KEY="LEFT"  ;;
                *) REPLY_KEY="$k1$k2$k3" ;;
            esac
        else
            REPLY_KEY="$k1$k2"
        fi
    elif [[ "$k1" == "" ]]; then
        REPLY_KEY="ENTER"
    elif [[ "$k1" == $'\x7f' ]]; then
        REPLY_KEY="BACKSPACE"
    else
        REPLY_KEY="$k1"
    fi
}

# Versão com timeout (para auto-refresh): retorna 0 se leu, 1 se timeout
# input::read_key_timeout 2  →  espera até 2s
input::read_key_timeout() {
    local secs=${1:-2}
    REPLY_KEY=""
    local k1 k2 k3
    if ! IFS= read -rsn1 -t "$secs" k1; then return 1; fi
    if [[ "$k1" == $'\x1b' ]]; then
        IFS= read -rsn1 -t 0.0005 k2 || { REPLY_KEY="ESC"; return 0; }
        if [[ "$k2" == "[" ]]; then
            IFS= read -rsn1 -t 0.0005 k3
            case "$k3" in
                A) REPLY_KEY="UP"    ;;
                B) REPLY_KEY="DOWN"  ;;
                C) REPLY_KEY="RIGHT" ;;
                D) REPLY_KEY="LEFT"  ;;
                *) REPLY_KEY="$k1$k2$k3" ;;
            esac
        else
            REPLY_KEY="$k1$k2"
        fi
    elif [[ "$k1" == "" ]]; then REPLY_KEY="ENTER"
    elif [[ "$k1" == $'\x7f' ]]; then REPLY_KEY="BACKSPACE"
    else REPLY_KEY="$k1"
    fi
    return 0
}

# ─── Prompts tradicionais (read com Enter) ───────────────────────────────────
# input::read_required "Nome do banco" [secret]
input::read_required() {
    local prompt=$1 mode=${2:-}
    REPLY_VALUE=""
    while :; do
        if [[ "$mode" == "secret" ]]; then
            printf '  %s%s%s %s%s%s %s(oculto)%s: ' \
                "$BOLD$CLR_ACCENT" "$GLYPH_ARROW" "$NC" \
                "$CLR_FG" "$prompt" "$NC" \
                "$DIM$CLR_MUTED" "$NC"
            IFS= read -rs REPLY_VALUE; printf '\n'
        else
            printf '  %s%s%s %s%s%s: ' \
                "$BOLD$CLR_ACCENT" "$GLYPH_ARROW" "$NC" \
                "$CLR_FG" "$prompt" "$NC"
            IFS= read -r REPLY_VALUE
        fi
        if [[ -z "$REPLY_VALUE" ]]; then
            ui::error "Valor não pode ser vazio."
            return 1
        fi
        return 0
    done
}

# input::read_optional "Banco destino" [default]
input::read_optional() {
    local prompt=$1 default=${2:-}
    REPLY_VALUE=""
    if [[ -n "$default" ]]; then
        printf '  %s%s%s %s%s%s %s(enter = %s)%s: ' \
            "$BOLD$CLR_ACCENT" "$GLYPH_ARROW" "$NC" \
            "$CLR_FG" "$prompt" "$NC" \
            "$DIM$CLR_MUTED" "$default" "$NC"
    else
        printf '  %s%s%s %s%s%s %s(opcional)%s: ' \
            "$BOLD$CLR_ACCENT" "$GLYPH_ARROW" "$NC" \
            "$CLR_FG" "$prompt" "$NC" \
            "$DIM$CLR_MUTED" "$NC"
    fi
    IFS= read -r REPLY_VALUE
    [[ -z "$REPLY_VALUE" ]] && REPLY_VALUE="$default"
}

# input::confirm "Confirma X?"  →  rc 0 se s/S/y/Y
input::confirm() {
    local prompt=$1 ans
    printf '  %s%s?%s %s%s%s %s(s/N)%s: ' \
        "$BOLD$CLR_WARN" "" "$NC" \
        "$CLR_FG" "$prompt" "$NC" \
        "$DIM$CLR_MUTED" "$NC"
    IFS= read -r ans
    [[ "$ans" =~ ^[sSyY]$ ]]
}

# Confirmação destrutiva: exige digitar um token específico (ex: "CONFIRMAR")
input::confirm_destructive() {
    local token=$1 ans
    printf '  %s%s%s digite %s%s%s para prosseguir: ' \
        "$BOLD$CLR_WARN" "$GLYPH_WARN" "$NC" \
        "$BOLD$CLR_ERR" "$token" "$NC"
    IFS= read -r ans
    [[ "$ans" == "$token" ]]
}

# ─── Seleção em lista (usa fzf se houver, senão menu numérico) ───────────────
# input::choose "Escolha um item" item1 item2 item3 ...
# resultado em REPLY_CHOICE, rc != 0 se cancelado/vazio
input::choose() {
    local prompt=$1; shift
    REPLY_CHOICE=""
    (( $# == 0 )) && return 1

    if input::has_fzf && core::is_tty; then
        local result
        result=$(printf '%s\n' "$@" | fzf \
            --prompt="  $prompt › " \
            --height=40% --reverse --border=rounded \
            --color="prompt:51,pointer:51,marker:114,header:245,border:45")
        [[ -z "$result" ]] && return 1
        REPLY_CHOICE="$result"
        return 0
    fi

    # Fallback: menu numérico
    printf '\n'
    local idx=1
    for item in "$@"; do
        printf '  %s%s%2d%s %s%s%s %s%s%s\n' \
            "$BOLD$CLR_ACCENT" "" "$idx" "$NC" \
            "$DIM$CLR_FAINT" "│" "$NC" \
            "$CLR_FG" "$item" "$NC"
        idx=$((idx + 1))
    done
    printf '\n'
    local choice
    printf '  %s%s%s %s%s%s: ' \
        "$BOLD$CLR_ACCENT" "$GLYPH_ARROW" "$NC" \
        "$CLR_FG" "$prompt" "$NC"
    IFS= read -r choice
    [[ ! "$choice" =~ ^[0-9]+$ ]] && return 1
    (( choice < 1 || choice > $# )) && return 1
    local args=("$@")
    REPLY_CHOICE="${args[$((choice-1))]}"
    return 0
}

# ─── Seleção de backup por extensão ──────────────────────────────────────────
# input::choose_backup_file <db> <ext1> [ext2 ...]  →  REPLY_FILE
input::choose_backup_file() {
    local db=$1; shift
    local exts=("$@")
    local bdir="$DBM_BACKUP_DIR/$db"
    REPLY_FILE=""
    core::ensure_dir "$bdir"

    local -a files=()
    local ext f
    for ext in "${exts[@]}"; do
        for f in "$bdir"/*."$ext" "$bdir"/*."${ext^^}"; do
            [[ -f "$f" ]] && files+=("$(basename "$f")")
        done
    done
    if (( ${#files[@]} == 0 )); then
        ui::warn "Nenhum arquivo encontrado em $bdir"
        ui::info "Extensões aceitas: ${exts[*]}"
        return 1
    fi

    ui::info "Arquivos disponíveis em ${BOLD}$bdir${NC}:"
    input::choose "Arquivo de backup" "${files[@]}" || return 1
    REPLY_FILE="$REPLY_CHOICE"
}

# Aliases retrocompat
read_required()        { input::read_required "$@"; }
read_prompt()          { input::read_optional "$@"; }
confirm()              { input::confirm "$@"; }
choose_backup_file()   { input::choose_backup_file "$@"; }
