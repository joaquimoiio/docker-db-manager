#!/usr/bin/env bash
# dashboard.sh — view principal interativa com navegação single-key estilo
# lazydocker. Redesenha somente em resposta a tecla (sem auto-refresh).
# Sai do alt-screen quando ações precisam de TTY bruto (logs -f, exec).

[[ -n "${_DBM_DASH_LOADED:-}" ]] && return 0
_DBM_DASH_LOADED=1

: "${_DBM_UI_LOADED:?}"
: "${_DBM_DOCKER_LOADED:?}"
: "${_DBM_LIFECYCLE_LOADED:?}"
: "${_DBM_LOGS_LOADED:?}"
: "${_DBM_INPUT_LOADED:?}"

# ─── Render principal ────────────────────────────────────────────────────────
dashboard::_render() {
    local selected=$1

    # Banner ASCII personalizado no topo
    ui::banner
    printf '  %s%sgestão elegante de containers PostgreSQL · MySQL · Oracle · SQL Server%s\n\n' \
        "$DIM$CLR_MUTED" "" "$NC"

    # Atualiza stats em batch
    docker::_refresh_stats

    ui::table_header \
        " " 3 "BANCO" 13 "STATUS" 13 "CPU" 8 "MEM" 12 "PORTA" 8 "CONTAINER" 22

    local i=0 db name port label color glyph state pill cpumem cpu mem prefix row_color
    for db in "${DB_TYPES[@]}"; do
        name=$(core::db_config "$db" CONTAINER)
        port=$(core::db_config "$db" PORT)
        label=$(core::db_config "$db" LABEL)
        color=$(db_color "$db")
        glyph=$(db_glyph "$db")
        state=$(docker::state "$name")
        case "$state" in
            running) pill="${CLR_OK}${BOLD}${GLYPH_DOT} rodando${NC}" ;;
            exited|created|paused) pill="${CLR_WARN}${BOLD}${GLYPH_SQUARE} parado${NC}" ;;
            *) pill="${DIM}${CLR_MUTED}${GLYPH_RING} ausente${NC}" ;;
        esac
        cpumem="${_DOCK_STATS_MAP[$name]:-}"
        if [[ -n "$cpumem" ]]; then
            cpu="${cpumem%%|*}"; mem="${cpumem##*|}"
        else
            cpu="—"; mem="—"
        fi

        if (( i == selected )); then
            prefix="${BOLD}${CLR_ACCENT}▶${NC}"
            row_color="${BOLD}${CLR_FG}"
        else
            prefix=" "
            row_color="${CLR_FG}"
        fi

        ui::table_row \
            "$prefix" 3 \
            "${color}${BOLD}${glyph} ${label}${NC}" 13 \
            "$pill" 13 \
            "${row_color}${cpu}${NC}" 8 \
            "${row_color}${mem}${NC}" 12 \
            "${DIM}${CLR_MUTED}:${NC}${row_color}${port}${NC}" 8 \
            "${row_color}${name}${NC}" 22
        i=$(( i + 1 ))
    done

    # Keybar — atalhos contextuais para a linha selecionada
    ui::keybar \
        "↑↓/jk" "navegar" \
        "ENTER" "gerenciar" \
        "s" "start" \
        "x" "stop" \
        "r" "restart" \
        "e" "exec" \
        "l" "logs" \
        "d" "delete" \
        "q" "sair"

    printf '\n  %s%sseleção: %s%s%s%s\n' \
        "$DIM$CLR_MUTED" "$GLYPH_BULLET " \
        "$BOLD$CLR_FG" "${DB_TYPES[$selected]}" "$NC" "$NC"
}

# ─── Helper de ação ──────────────────────────────────────────────────────────
dashboard::_run_action() {
    local action=$1 db=$2
    core::cls
    # manage tem seu próprio banner e loop — entra direto.
    [[ "$action" == "manage" ]] && { manage::menu "$db"; return; }

    ui::db_banner "$db"
    case "$action" in
        start)   lifecycle::start   "$db" ;;
        stop)    lifecycle::stop    "$db" ;;
        restart) lifecycle::restart "$db" ;;
        delete)  lifecycle::delete  "$db" ;;
        logs)    logs::tail         "$db" 50 ;;
        exec)
            core::altscreen_off
            lifecycle::exec "$db"
            core::altscreen_on
            return
            ;;
    esac
    ui::pause
}

# ─── Splash inicial (banner uma vez) ─────────────────────────────────────────
dashboard::_splash() {
    core::cls
    ui::banner
    printf '  %sgerenciamento elegante de containers PostgreSQL · MySQL · Oracle · SQL Server%s\n\n' \
        "$DIM$CLR_MUTED" "$NC"
    # Sem sleep: o primeiro render do dashboard já chega imediatamente.
}

# ─── Loop principal ──────────────────────────────────────────────────────────
dashboard::run() {
    dashboard::_splash
    core::altscreen_on
    core::hide_cursor

    local selected=0 max=$(( ${#DB_TYPES[@]} - 1 ))
    local k

    while true; do
        core::home
        core::clear_below
        dashboard::_render "$selected"

        input::read_key
        k=$REPLY_KEY

        case "$k" in
            UP|k)   (( selected > 0 )) && selected=$(( selected - 1 )) ;;
            DOWN|j) (( selected < max )) && selected=$(( selected + 1 )) ;;
            [1-9])
                local n=$(( k - 1 ))
                (( n <= max )) && selected=$n
                ;;
            s) core::show_cursor; dashboard::_run_action start   "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            x) core::show_cursor; dashboard::_run_action stop    "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            r) core::show_cursor; dashboard::_run_action restart "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            l) core::show_cursor; dashboard::_run_action logs    "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            e) core::show_cursor; dashboard::_run_action exec    "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            d) core::show_cursor; dashboard::_run_action delete  "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            m|ENTER|RIGHT) core::show_cursor; dashboard::_run_action manage  "${DB_TYPES[$selected]}"; core::hide_cursor ;;
            q|Q|ESC) break ;;
            *) ;;  # ignora desconhecida
        esac
    done

    core::show_cursor
    core::altscreen_off
    printf '\n  %s%s%s%s  %s%saté a próxima!%s\n\n' \
        "$BOLD" "$CLR_HOT" "$GLYPH_STAR" "$NC" "$ITALIC" "$CLR_FG" "$NC"
}
