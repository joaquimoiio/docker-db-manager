#!/usr/bin/env bash
# ui.sh — primitivas visuais. Toda saída formatada do app passa por aqui.
# Permite trocar/aperfeiçoar o visual em um único lugar.

[[ -n "${_DBM_UI_LOADED:-}" ]] && return 0
_DBM_UI_LOADED=1

# Depende de: theme.sh, core.sh
: "${_DBM_THEME_LOADED:?source lib/theme.sh first}"
: "${_DBM_CORE_LOADED:?source lib/core.sh first}"

# ─── Util: largura visível (descarta ANSI) ───────────────────────────────────
ui::_strip_ansi() {
    # remove sequências CSI (ESC[...letra)
    printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
}

ui::_visible_len() {
    local s; s=$(ui::_strip_ansi "$1")
    printf '%d' "${#s}"
}

# Repete um caractere N vezes (eficiente, sem loop bash quando possível)
ui::_repeat() {
    local ch=$1 n=$2 out=""
    (( n <= 0 )) && return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$ch}"
}

# Padding à direita preservando ANSI (alinha por largura visível)
ui::_padr() {
    local s=$1 width=$2
    local vlen; vlen=$(ui::_visible_len "$s")
    local pad=$(( width - vlen ))
    (( pad < 0 )) && pad=0
    printf '%s%*s' "$s" "$pad" ''
}

# ─── Linhas de mensagem (substituem print_*) ─────────────────────────────────
ui::ok()    { printf '  %s%s%s%s %s%s%s\n'   "$CLR_OK"   "$BOLD" "$GLYPH_OK"   "$NC" "$CLR_FG" "$1" "$NC"; }
ui::info()  { printf '  %s%s%s%s  %s%s%s\n'  "$CLR_INFO" "$BOLD" "$GLYPH_INFO" "$NC" "$CLR_FG" "$1" "$NC"; }
ui::warn()  { printf '  %s%s%s%s %s%s%s\n'   "$CLR_WARN" "$BOLD" "$GLYPH_WARN" "$NC" "$CLR_FG" "$1" "$NC"; }
ui::error() { printf '  %s%s%s%s %s%s%s\n'   "$CLR_ERR"  "$BOLD" "$GLYPH_ERR"  "$NC" "$CLR_FG" "$1" "$NC"; }
ui::muted() { printf '  %s%s%s\n'             "$DIM"      "$CLR_MUTED" "$1$NC"; }

# Aliases de compatibilidade durante a transição
print_ok()    { ui::ok    "$1"; }
print_info()  { ui::info  "$1"; }
print_warn()  { ui::warn  "$1"; }
print_error() { ui::error "$1"; }

# ─── Separadores e seções ────────────────────────────────────────────────────
ui::hr() {
    local cols width line
    cols=$(core::term_cols); width=$(( cols - 4 ))
    (( width > 76 )) && width=76
    line=$(ui::_repeat "$BOX_H" "$width")
    printf '  %s%s%s\n' "$DIM$CLR_FAINT" "$line" "$NC"
}

ui::section() {
    printf '\n  %s%s%s%s %s%s%s\n' "$BOLD" "$CLR_ACCENT" "$GLYPH_STAR" "$NC" "$BOLD$CLR_FG" "$1" "$NC"
    ui::hr
}

# Alias retro
section() { ui::section "$1"; }
sep()     { ui::hr; }

# ─── Pílula de status (uma linha, com cor) ───────────────────────────────────
ui::status_pill() {
    local name=$1
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        printf '%s%s%s rodando%s'    "$CLR_OK"   "$BOLD" "$GLYPH_DOT"    "$NC"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        printf '%s%s%s parado%s'     "$CLR_WARN" "$BOLD" "$GLYPH_SQUARE" "$NC"
    else
        printf '%s%s%s ausente%s'    "$DIM$CLR_MUTED" "$BOLD" "$GLYPH_RING" "$NC"
    fi
}
status_pill() { ui::status_pill "$1"; }

# ─── Painel (caixa com título) ───────────────────────────────────────────────
# Uso:
#   ui::panel_open "Conexão" [largura]
#   ui::panel_row "porta" "5432"
#   ui::panel_row "host"  "localhost"
#   ui::panel_close
ui::panel_open() {
    local title=$1 width=${2:-58}
    local tlen; tlen=$(ui::_visible_len "$title")
    local rest=$(( width - tlen - 4 ))
    (( rest < 2 )) && rest=2
    local fill; fill=$(ui::_repeat "$BOX_H" "$rest")
    printf '\n  %s%s%s %s%s%s %s%s%s\n' \
        "$CLR_ACCENT2" "$BOX_TL$BOX_H" "$NC" \
        "$BOLD$CLR_FG" "$title" "$NC" \
        "$CLR_ACCENT2" "$fill$BOX_TR" "$NC"
    _UI_PANEL_W=$width
}

ui::panel_row() {
    local key=$1 val=$2
    printf '  %s%s%s  %s%-9s%s %s%s%s\n' \
        "$CLR_ACCENT2" "$BOX_V" "$NC" \
        "$DIM$CLR_MUTED" "$key" "$NC" \
        "$BOLD$CLR_FG" "$val" "$NC"
}

ui::panel_text() {
    local txt=$1
    printf '  %s%s%s  %s%s%s\n' \
        "$CLR_ACCENT2" "$BOX_V" "$NC" \
        "$CLR_FG" "$txt" "$NC"
}

ui::panel_close() {
    local width=${_UI_PANEL_W:-58}
    local fill; fill=$(ui::_repeat "$BOX_H" "$(( width - 2 ))")
    printf '  %s%s%s%s\n' "$CLR_ACCENT2" "$BOX_BL" "$fill$BOX_BR" "$NC"
}

# ─── Painel destrutivo (vermelho, para confirmações) ─────────────────────────
ui::danger_box() {
    local title=$1; shift
    local width=64
    local tlen; tlen=$(ui::_visible_len "$title")
    local fill; fill=$(ui::_repeat "$BOX_H" "$(( width - tlen - 4 ))")
    printf '\n  %s%s%s %s%s%s %s%s%s\n' \
        "$BOLD$CLR_ERR" "$BOX_TL$BOX_H" "$NC" \
        "$BOLD$CLR_ERR" "$title" "$NC" \
        "$BOLD$CLR_ERR" "$fill$BOX_TR" "$NC"
    local line
    for line in "$@"; do
        printf '  %s%s%s  %s%s%s\n' "$BOLD$CLR_ERR" "$BOX_V" "$NC" "$CLR_FG" "$line" "$NC"
    done
    fill=$(ui::_repeat "$BOX_H" "$(( width - 2 ))")
    printf '  %s%s%s%s\n\n' "$BOLD$CLR_ERR" "$BOX_BL" "$fill$BOX_BR" "$NC"
}

# ─── Tabela (header + rows, largura por coluna) ──────────────────────────────
# Uso:
#   ui::table_header "STATUS" 12 "CPU" 7 "MEM" 8 "PORT" 7 "CONTAINER" 22
#   ui::table_row "● rodando" 12 "2.1%" 7 "180M" 8 "5432" 7 "postgres-dev" 22
declare -ga _UI_TABLE_WIDTHS=()

ui::table_header() {
    _UI_TABLE_WIDTHS=()
    local total=0 col cell
    printf '  '
    while (( $# >= 2 )); do
        col=$1; cell=$2; shift 2
        _UI_TABLE_WIDTHS+=("$cell")
        printf '%s%s%s' "$BOLD$CLR_MUTED" "$(ui::_padr "$col" "$cell")" "$NC"
        total=$(( total + cell ))
    done
    printf '\n  %s%s%s\n' "$DIM$CLR_FAINT" "$(ui::_repeat "$BOX_H" "$total")" "$NC"
}

ui::table_row() {
    local i=0 cell w
    printf '  '
    while (( $# >= 2 )); do
        cell=$1; w=$2; shift 2
        printf '%s' "$(ui::_padr "$cell" "$w")"
        i=$(( i + 1 ))
    done
    printf '\n'
}

# ─── Barra de atalhos no rodapé (estilo lazydocker) ──────────────────────────
# Uso: ui::keybar "s" "start" "x" "stop" "l" "logs" "q" "quit"
ui::keybar() {
    local out=""
    while (( $# >= 2 )); do
        out+="$BOLD$CLR_ACCENT[$1]$NC $CLR_MUTED$2$NC  "
        shift 2
    done
    printf '\n  %s\n' "$out"
}

# ─── Spinner ─────────────────────────────────────────────────────────────────
# spinner_run "mensagem" comando args... → executa em bg mostrando spinner
ui::spinner_run() {
    local message=$1; shift
    if ! core::anim_enabled; then "$@"; return $?; fi
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local tmp; tmp=$(mktemp)
    ( "$@" >"$tmp" 2>&1 ) &
    local pid=$!
    core::hide_cursor
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s%s%s  %s%s%s' "$CLR_ACCENT" "${frames[i]}" "$NC" "$DIM$CLR_FG" "$message" "$NC"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.07
    done
    wait "$pid"; local rc=$?
    printf '\r\033[K'
    core::show_cursor
    if (( rc != 0 )) && [[ -s "$tmp" ]]; then cat "$tmp"; fi
    rm -f "$tmp"
    return $rc
}
spinner_run() { ui::spinner_run "$@"; }

# Barra cheia rápida (feedback pós-operação curta)
ui::flash_bar() {
    core::anim_enabled || return 0
    local color=${1:-$CLR_OK} width=42 i
    core::hide_cursor
    for ((i=1; i<=width; i++)); do
        printf '\r  %s%s%s' "$color" "$(ui::_repeat ━ "$i")" "$NC"
        sleep 0.004
    done
    printf '\r\033[K'
    core::show_cursor
}
flash_bar() { ui::flash_bar "$@"; }

# ─── Banner (splash inicial — uma vez por sessão) ────────────────────────────
ui::banner() {
    local L1="$G1    ██████╗ ██████╗     ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗ $NC"
    local L2="$G2    ██╔══██╗██╔══██╗    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗$NC"
    local L3="$G3    ██║  ██║██████╔╝    ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝$NC"
    local L4="$G4    ██║  ██║██╔══██╗    ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗$NC"
    local L5="$G5    ██████╔╝██████╔╝    ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║$NC"
    local L6="$G6    ╚═════╝ ╚═════╝     ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝$NC"
    printf '\n%s\n%s\n%s\n%s\n%s\n%s\n\n' "$L1" "$L2" "$L3" "$L4" "$L5" "$L6"
}

# Barra de título compacta (usada dentro do app, não consome tela inteira)
ui::titlebar() {
    local title=$1 sub=${2:-}
    local cols; cols=$(core::term_cols)
    local width=$(( cols - 4 ))
    (( width > 76 )) && width=76
    local tline; tline=$(ui::_repeat "$BOX_H" "$width")
    printf '\n  %s%s%s\n' "$CLR_ACCENT2" "$tline" "$NC"
    printf '  %s%s%s%s' "$BOLD$CLR_ACCENT" "$GLYPH_STAR" " $title" "$NC"
    [[ -n "$sub" ]] && printf '   %s%s%s' "$DIM$CLR_MUTED" "$sub" "$NC"
    printf '\n  %s%s%s\n\n' "$CLR_ACCENT2" "$tline" "$NC"
}

# Header colorido por banco (substitui ascii art individual de cada DB)
ui::db_header() {
    local db=$1 ctx=${2:-}
    local label color glyph
    label=$(core::db_config "$db" LABEL)
    color=$(db_color "$db")
    glyph=$(db_glyph "$db")
    local tagline; tagline=$(core::db_config "$db" TAGLINE)
    local cols; cols=$(core::term_cols)
    local width=$(( cols - 4 )); (( width > 76 )) && width=76
    local tline; tline=$(ui::_repeat "$BOX_H" "$width")
    printf '\n  %s%s%s\n' "$color" "$tline" "$NC"
    printf '  %s%s %s%s   %s%s%s' "$BOLD$color" "$glyph" "$label" "$NC" "$DIM$CLR_MUTED" "$tagline" "$NC"
    [[ -n "$ctx" ]] && printf '   %s· %s%s' "$DIM$CLR_MUTED" "$ctx" "$NC"
    printf '\n  %s%s%s\n\n' "$color" "$tline" "$NC"
}

# ─── Pause / prompt simples ──────────────────────────────────────────────────
ui::pause() {
    printf '\n  %s%s pressione %sENTER%s%s para continuar%s ' \
        "$DIM$CLR_MUTED" "$GLYPH_ARROW" "$BOLD$CLR_FG" "$NC" "$DIM$CLR_MUTED" "$NC"
    read -r _
}
pause() { ui::pause; }
