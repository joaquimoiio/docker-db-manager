#!/usr/bin/env bash
# lifecycle.sh — start/stop/restart/delete/exec de containers de banco.
# Delega criação para o módulo específico (<db>_create_container) e leitura de
# credenciais para <db>_show_credentials.

[[ -n "${_DBM_LIFECYCLE_LOADED:-}" ]] && return 0
_DBM_LIFECYCLE_LOADED=1

: "${_DBM_UI_LOADED:?source lib/ui.sh first}"
: "${_DBM_DOCKER_LOADED:?source lib/docker.sh first}"

# ─── start ───────────────────────────────────────────────────────────────────
lifecycle::start() {
    local db=$1
    local name port label
    name=$(core::db_config "$db" CONTAINER)
    port=$(core::db_config "$db" PORT)
    label=$(core::db_config "$db" LABEL)

    core::ensure_dir "$DBM_BACKUP_DIR/$db"

    if docker::running "$name"; then
        ui::warn "Container ${BOLD}$name${NC} já está rodando na porta ${BOLD}$port${NC}."
        return 0
    fi

    if docker::port_in_use "$port"; then
        ui::error "Porta ${BOLD}$port${NC} já está em uso por outro processo no host."
        ui::muted "use: sudo lsof -i :$port  para descobrir qual."
        return 1
    fi

    if docker::exists "$name"; then
        ui::spinner_run "iniciando container '$name'" docker start "$name" >/dev/null
    else
        ui::info "Criando container ${BOLD}$name${NC} ($label)..."
        ui::spinner_run "baixando imagem e criando container" "${db}_create_container"
    fi
    local rc=$?
    docker::ps_invalidate
    if (( rc != 0 )); then
        ui::error "Falha ao iniciar '$name'."
        return $rc
    fi

    ui::flash_bar "$CLR_OK"
    ui::ok "Container ${BOLD}$name${NC} iniciado."

    ui::panel_open "Conexão"
    ui::panel_row "host"   "localhost"
    ui::panel_row "porta"  "$port"
    ui::panel_row "backup" "$DBM_BACKUP_DIR/$db"
    "${db}_show_credentials"
    ui::panel_close

    # Nota específica do módulo (ex: Oracle leva 60s, SQL Server 30s)
    type "${db}_start_note" &>/dev/null && "${db}_start_note"
}

# ─── stop ────────────────────────────────────────────────────────────────────
lifecycle::stop() {
    local db=$1
    local name; name=$(core::db_config "$db" CONTAINER)
    if ! docker::exists "$name"; then
        ui::error "Container ${BOLD}$name${NC} não existe."
        return 1
    fi
    if ! docker::running "$name"; then
        ui::warn "Container ${BOLD}$name${NC} já está parado."
        return 0
    fi
    ui::spinner_run "parando $name" docker stop "$name" >/dev/null
    docker::ps_invalidate
    ui::ok "Container parado. ${DIM}${CLR_MUTED}Dados preservados.${NC}"
}

# ─── restart ─────────────────────────────────────────────────────────────────
lifecycle::restart() {
    local db=$1
    local name; name=$(core::db_config "$db" CONTAINER)
    if ! docker::exists "$name"; then
        ui::warn "Container não existe. Criando do zero..."
        lifecycle::start "$db"
        return $?
    fi
    ui::spinner_run "reiniciando $name" docker restart "$name" >/dev/null
    docker::ps_invalidate
    ui::ok "Container ${BOLD}$name${NC} reiniciado."
}

# ─── delete (destrutivo: pede CONFIRMAR digitado) ────────────────────────────
lifecycle::delete() {
    local db=$1
    local name; name=$(core::db_config "$db" CONTAINER)
    if ! docker::exists "$name"; then
        ui::error "Container ${BOLD}$name${NC} não existe."
        return 1
    fi

    ui::danger_box "ATENÇÃO — operação destrutiva" \
        "Remove o container ${BOLD}$name${NC}" \
        "${BOLD}${CLR_ERR}TODOS os dados internos${NC} serão perdidos." \
        "${DIM}${CLR_MUTED}Arquivos em backups/ NÃO serão tocados.${NC}"

    if ! input::confirm_destructive "CONFIRMAR"; then
        ui::info "Cancelado."
        return 0
    fi
    if docker::running "$name"; then
        ui::spinner_run "parando container" docker stop "$name" >/dev/null
    fi
    ui::spinner_run "removendo container" docker rm "$name" >/dev/null
    docker::ps_invalidate
    ui::ok "Container ${BOLD}$name${NC} removido."
}

# ─── exec: abre shell interativo dentro do container, no cliente do banco ────
# Cada módulo define <db>_shell_cmd (array) com o comando do cliente.
# Fallback: bash.
lifecycle::exec() {
    local db=$1
    local name; name=$(core::db_config "$db" CONTAINER)
    if ! docker::running "$name"; then
        ui::error "Container ${BOLD}$name${NC} não está rodando."
        return 1
    fi
    if type "${db}_shell_cmd" &>/dev/null; then
        ui::info "Abrindo ${BOLD}${db}${NC} client... ${DIM}${CLR_MUTED}(Ctrl-D para sair)${NC}"
        "${db}_shell_cmd"
    else
        ui::info "Abrindo bash em ${BOLD}$name${NC}... ${DIM}${CLR_MUTED}(Ctrl-D para sair)${NC}"
        docker exec -it "$name" bash
    fi
}
