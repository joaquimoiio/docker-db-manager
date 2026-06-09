#!/usr/bin/env bash
# Módulo PostgreSQL.

POSTGRES_LABEL="PostgreSQL"
POSTGRES_TAGLINE="objeto-relacional · ACID · open source"
POSTGRES_ARCHS="amd64 arm64"   # imagem oficial multi-arch
POSTGRES_CONTAINER="postgres-dev"
POSTGRES_IMAGE="${DBM_POSTGRES_IMAGE:-postgres:16}"
POSTGRES_PORT="${DBM_POSTGRES_PORT:-5432}"
POSTGRES_USER="${DBM_POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${DBM_POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${DBM_POSTGRES_DB:-devdb}"

postgres_create_container() {
    docker run -d \
        --name "$POSTGRES_CONTAINER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -p "${POSTGRES_PORT}:5432" \
        -v "$DBM_BACKUP_DIR/postgres:/backups" \
        --restart unless-stopped \
        "$POSTGRES_IMAGE" >/dev/null
}

postgres_show_credentials() {
    ui::panel_row "usuário" "$POSTGRES_USER"
    ui::panel_row "senha"   "$POSTGRES_PASSWORD"
    ui::panel_row "banco"   "$POSTGRES_DB"
}

postgres_shell_cmd() {
    docker exec -it "$POSTGRES_CONTAINER" \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}

postgres_exec() {
    docker exec "$POSTGRES_CONTAINER" \
        psql -U "$POSTGRES_USER" -c "$1" 2>&1
}

postgres_list_databases() {
    db::list_section "Bancos de dados" \
        docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -c "\l"
}

postgres_create_database() {
    input::read_required "Nome do novo banco" || return
    local dbname="$REPLY_VALUE"
    db::action "Banco '$dbname' criado" \
        docker exec "$POSTGRES_CONTAINER" createdb -U "$POSTGRES_USER" "$dbname"
}

postgres_drop_database() {
    postgres_list_databases
    printf '\n'
    input::read_required "Nome do banco a excluir" || return
    local dbname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$dbname'?" || { ui::info "Cancelado."; return; }
    db::action "Banco '$dbname' excluído" \
        docker exec "$POSTGRES_CONTAINER" dropdb -U "$POSTGRES_USER" "$dbname"
}

postgres_list_users() {
    db::list_section "Usuários" \
        docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -c "\du"
}

postgres_create_user() {
    input::read_required "Nome do novo usuário" || return
    local uname="$REPLY_VALUE"
    input::read_required "Senha" secret || return
    local upass="$REPLY_VALUE"
    if postgres_exec "CREATE USER \"$uname\" WITH PASSWORD '$upass';" >/dev/null; then
        ui::ok "Usuário '$uname' criado."
    else
        ui::error "Falha ao criar usuário."
    fi
}

postgres_drop_user() {
    postgres_list_users
    printf '\n'
    input::read_required "Nome do usuário a excluir" || return
    local uname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$uname'?" || { ui::info "Cancelado."; return; }
    db::action "Usuário '$uname' excluído" \
        docker exec "$POSTGRES_CONTAINER" dropuser -U "$POSTGRES_USER" "$uname"
}

postgres_restore() {
    input::choose_backup_file postgres sql dump backup || return
    local file="$REPLY_FILE"

    postgres_list_databases
    printf '\n'
    local dbname
    input::read_optional "Banco destino (enter = criar novo)"
    dbname="$REPLY_VALUE"
    if [[ -z "$dbname" ]]; then
        input::read_required "Nome do novo banco" || return
        dbname="$REPLY_VALUE"
        docker exec "$POSTGRES_CONTAINER" createdb -U "$POSTGRES_USER" "$dbname" >/dev/null 2>&1
        ui::ok "Banco '$dbname' criado."
    fi

    ui::info "Restaurando '$file' em '$dbname'..."
    local ext="${file##*.}"
    if [[ "${ext,,}" == "sql" ]]; then
        docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$dbname" -f "/backups/$file" 2>&1
    else
        docker exec "$POSTGRES_CONTAINER" pg_restore -U "$POSTGRES_USER" -d "$dbname" -v "/backups/$file" 2>&1
    fi
    ui::ok "Restauração de '$file' concluída."
}
