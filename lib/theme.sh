#!/usr/bin/env bash
# theme.sh — paleta, glifos e estilos. Fonte única de verdade visual.
# Trocar tema = editar este arquivo. Nenhum outro módulo deve hardcodar cores.

[[ -n "${_DBM_THEME_LOADED:-}" ]] && return 0
_DBM_THEME_LOADED=1

# ─── Estilos base ────────────────────────────────────────────────────────────
NC=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
ITALIC=$'\033[3m'
UNDER=$'\033[4m'

# ─── Cores semânticas (256-color, otimizadas para fundo escuro) ──────────────
CLR_FG=$'\033[38;5;255m'        # texto principal
CLR_MUTED=$'\033[38;5;245m'     # texto secundário
CLR_FAINT=$'\033[38;5;240m'     # bordas, separadores

CLR_OK=$'\033[38;5;114m'        # verde sucesso
CLR_WARN=$'\033[38;5;221m'      # amarelo aviso
CLR_ERR=$'\033[38;5;203m'       # vermelho erro
CLR_INFO=$'\033[38;5;75m'       # azul info

CLR_ACCENT=$'\033[38;5;51m'     # ciano vivo — destaque primário
CLR_ACCENT2=$'\033[38;5;45m'    # ciano — destaque secundário
CLR_HOT=$'\033[38;5;213m'       # magenta — destaque alternativo

# Aliases legados (compat com módulos antigos durante a migração)
RED=$CLR_ERR
GREEN=$CLR_OK
YELLOW=$CLR_WARN
BLUE=$CLR_INFO
CYAN=$CLR_ACCENT
MAGENTA=$CLR_HOT
GRAY=$CLR_MUTED
WHITE=$CLR_FG
G1=$'\033[38;5;39m'  G2=$CLR_ACCENT2  G3=$CLR_ACCENT
G4=$'\033[38;5;87m'  G5=$'\033[38;5;123m'  G6=$'\033[38;5;159m'

# ─── Cores por banco (usadas em badges, tabelas, headers) ────────────────────
db_color() {
    case "$1" in
        postgres)  printf '%s' $'\033[38;5;75m'  ;;  # azul postgres
        mysql)     printf '%s' $'\033[38;5;81m'  ;;  # ciano mysql
        oracle)    printf '%s' $'\033[38;5;208m' ;;  # laranja oracle
        sqlserver) printf '%s' $'\033[38;5;160m' ;;  # vermelho mssql
        *)         printf '%s' "$CLR_ACCENT"     ;;
    esac
}

db_glyph() {
    case "$1" in
        postgres)  printf '◆' ;;
        mysql)     printf '❖' ;;
        oracle)    printf '◉' ;;
        sqlserver) printf '▣' ;;
        *)         printf '◌' ;;
    esac
}

# ─── Glifos ──────────────────────────────────────────────────────────────────
GLYPH_OK="✔"
GLYPH_INFO="ℹ"
GLYPH_WARN="▲"
GLYPH_ERR="✖"
GLYPH_DOT="●"
GLYPH_RING="○"
GLYPH_SQUARE="■"
GLYPH_ARROW="›"
GLYPH_STAR="✦"
GLYPH_BULLET="•"
GLYPH_PLAY="▶"
GLYPH_STOP="■"
GLYPH_CYCLE="↺"
GLYPH_CROSS="✕"
GLYPH_LIST="≡"
GLYPH_PLUS="+"
GLYPH_BACK="←"
GLYPH_DOWN="↩"
GLYPH_GEAR="⚙"

# ─── Caracteres de box-drawing (perfis fino e duplo) ─────────────────────────
BOX_TL="╭"  BOX_TR="╮"  BOX_BL="╰"  BOX_BR="╯"
BOX_H="─"   BOX_V="│"
BOX_T_DOWN="┬"  BOX_T_UP="┴"  BOX_T_RIGHT="├"  BOX_T_LEFT="┤"  BOX_CROSS="┼"
