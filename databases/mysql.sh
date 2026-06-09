#!/usr/bin/env bash
# Módulo MySQL.

MYSQL_LABEL="MySQL"
MYSQL_TAGLINE="rápido · confiável · amplamente usado"
MYSQL_ARCHS="amd64 arm64"   # imagem oficial multi-arch
MYSQL_CONTAINER="mysql-dev"
MYSQL_IMAGE="${DBM_MYSQL_IMAGE:-mysql:8}"
MYSQL_PORT="${DBM_MYSQL_PORT:-3306}"
MYSQL_ROOT_PASSWORD="${DBM_MYSQL_ROOT_PASSWORD:-Root@123}"
MYSQL_DB="${DBM_MYSQL_DB:-devdb}"

mysql_create_container() {
    docker run -d \
        --name "$MYSQL_CONTAINER" \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
        -e MYSQL_DATABASE="$MYSQL_DB" \
        -p "${MYSQL_PORT}:3306" \
        -v "$DBM_BACKUP_DIR/mysql:/backups" \
        --restart unless-stopped \
        "$MYSQL_IMAGE" >/dev/null
}

mysql_show_credentials() {
    ui::panel_row "usuário" "root"
    ui::panel_row "senha"   "$MYSQL_ROOT_PASSWORD"
    ui::panel_row "banco"   "$MYSQL_DB"
}

mysql_shell_cmd() {
    docker exec -it "$MYSQL_CONTAINER" \
        mysql -u root -p"$MYSQL_ROOT_PASSWORD"
}

mysql_exec() {
    docker exec "$MYSQL_CONTAINER" \
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" --silent -e "$1" 2>&1
}

mysql_list_databases() {
    db::list_section "Bancos de dados" \
        docker exec "$MYSQL_CONTAINER" \
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;"
}

mysql_create_database() {
    input::read_required "Nome do novo banco" || return
    local dbname="$REPLY_VALUE"
    if mysql_exec "CREATE DATABASE \`$dbname\`;" >/dev/null; then
        ui::ok "Banco '$dbname' criado."
    else
        ui::error "Falha ao criar banco."
    fi
}

mysql_drop_database() {
    mysql_list_databases
    printf '\n'
    input::read_required "Nome do banco a excluir" || return
    local dbname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$dbname'?" || { ui::info "Cancelado."; return; }
    if mysql_exec "DROP DATABASE \`$dbname\`;" >/dev/null; then
        ui::ok "Banco '$dbname' excluído."
    else
        ui::error "Falha ao excluir banco."
    fi
}

mysql_list_users() {
    db::list_section "Usuários" \
        docker exec "$MYSQL_CONTAINER" \
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" \
        -e "SELECT User, Host, account_locked FROM mysql.user ORDER BY User;"
}

mysql_create_user() {
    input::read_required "Nome do novo usuário" || return
    local uname="$REPLY_VALUE"
    input::read_required "Senha" secret || return
    local upass="$REPLY_VALUE"
    input::read_optional "Banco a conceder acesso (enter = todos)"
    local dbname="$REPLY_VALUE"
    local grant_target
    if [[ -n "$dbname" ]]; then grant_target="\`${dbname}\`.*"; else grant_target="*.*"; fi
    if mysql_exec "CREATE USER '$uname'@'%' IDENTIFIED BY '$upass'; GRANT ALL PRIVILEGES ON ${grant_target} TO '$uname'@'%'; FLUSH PRIVILEGES;" >/dev/null; then
        ui::ok "Usuário '$uname' criado com acesso a '${dbname:-todos os bancos}'."
    else
        ui::error "Falha ao criar usuário."
    fi
}

mysql_drop_user() {
    mysql_list_users
    printf '\n'
    input::read_required "Nome do usuário a excluir" || return
    local uname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$uname'?" || { ui::info "Cancelado."; return; }
    if mysql_exec "DROP USER '$uname'@'%'; FLUSH PRIVILEGES;" >/dev/null; then
        ui::ok "Usuário '$uname' excluído."
    else
        ui::error "Falha ao excluir usuário."
    fi
}

mysql_restore() {
    input::choose_backup_file mysql sql || return
    local file="$REPLY_FILE"

    mysql_list_databases
    printf '\n'
    local dbname
    input::read_optional "Banco destino (enter = criar novo)"
    dbname="$REPLY_VALUE"
    if [[ -z "$dbname" ]]; then
        input::read_required "Nome do novo banco" || return
        dbname="$REPLY_VALUE"
        mysql_exec "CREATE DATABASE \`$dbname\`;" >/dev/null
        ui::ok "Banco '$dbname' criado."
    fi

    ui::info "Restaurando '$file' em '$dbname'..."
    docker exec -i "$MYSQL_CONTAINER" \
        mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$dbname" \
        < "$DBM_BACKUP_DIR/mysql/$file" 2>&1
    ui::ok "Restauração de '$file' concluída."
}
