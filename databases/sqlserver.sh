#!/usr/bin/env bash
# Módulo SQL Server.

SQLSERVER_LABEL="SQL Server"
SQLSERVER_TAGLINE="T-SQL · enterprise · Microsoft · 2022"
SQLSERVER_ARCHS="amd64"   # imagem mssql/server só tem build x86_64
SQLSERVER_CONTAINER="sqlserver-dev"
SQLSERVER_IMAGE="${DBM_SQLSERVER_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
SQLSERVER_PORT="${DBM_SQLSERVER_PORT:-1433}"
SQLSERVER_SA_PASSWORD="${DBM_SQLSERVER_SA_PASSWORD:-SqlServer@123}"

sqlserver_create_container() {
    docker run -d \
        --name "$SQLSERVER_CONTAINER" \
        -e ACCEPT_EULA=Y \
        -e SA_PASSWORD="$SQLSERVER_SA_PASSWORD" \
        -p "${SQLSERVER_PORT}:1433" \
        -v "$DBM_BACKUP_DIR/sqlserver:/var/opt/mssql/backup" \
        --restart unless-stopped \
        "$SQLSERVER_IMAGE" >/dev/null
}

sqlserver_show_credentials() {
    ui::panel_row "usuário" "sa"
    ui::panel_row "senha"   "$SQLSERVER_SA_PASSWORD"
}

sqlserver_shell_cmd() {
    docker exec -it "$SQLSERVER_CONTAINER" \
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" -No
}

sqlserver_start_note() {
    ui::warn "Aguarde ~30s para o SQL Server inicializar completamente."
}

sqlserver_exec() {
    docker exec "$SQLSERVER_CONTAINER" \
        /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" -No \
        -Q "$1" 2>&1
}

sqlserver_exec_db() {
    local dbname=$1
    docker exec "$SQLSERVER_CONTAINER" \
        /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" -No \
        -d "$dbname" \
        -Q "$2" 2>&1
}

sqlserver_list_databases() {
    db::list_section "Bancos de dados" \
        sqlserver_exec "SELECT name, state_desc FROM sys.databases WHERE database_id > 4 ORDER BY name;"
}

sqlserver_create_database() {
    input::read_required "Nome do novo banco" || return
    local dbname="$REPLY_VALUE"
    if sqlserver_exec "CREATE DATABASE [$dbname];" >/dev/null; then
        ui::ok "Banco '$dbname' criado."
    else
        ui::error "Falha ao criar banco."
    fi
}

sqlserver_drop_database() {
    sqlserver_list_databases
    printf '\n'
    input::read_required "Nome do banco a excluir" || return
    local dbname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$dbname'?" || { ui::info "Cancelado."; return; }
    if sqlserver_exec "ALTER DATABASE [$dbname] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbname];" >/dev/null; then
        ui::ok "Banco '$dbname' excluído."
    else
        ui::error "Falha ao excluir banco."
    fi
}

sqlserver_list_users() {
    db::list_section "Logins do SQL Server" \
        sqlserver_exec "SELECT name, type_desc, is_disabled FROM sys.server_principals WHERE type IN ('S','U') AND name NOT LIKE '##%' ORDER BY name;"
}

sqlserver_create_user() {
    sqlserver_list_databases
    printf '\n'
    input::read_required "Nome do novo login" || return
    local uname="$REPLY_VALUE"
    input::read_required "Senha (mín. 8 chars, maiúscula, número e símbolo)" secret || return
    local upass="$REPLY_VALUE"
    input::read_required "Banco para associar o usuário" || return
    local dbname="$REPLY_VALUE"
    if sqlserver_exec "CREATE LOGIN [$uname] WITH PASSWORD='$upass';" >/dev/null \
       && sqlserver_exec_db "$dbname" "CREATE USER [$uname] FOR LOGIN [$uname]; ALTER ROLE db_owner ADD MEMBER [$uname];" >/dev/null; then
        ui::ok "Login '$uname' criado e associado ao banco '$dbname' como db_owner."
    else
        ui::error "Falha ao criar usuário."
    fi
}

sqlserver_drop_user() {
    sqlserver_list_users
    printf '\n'
    input::read_required "Nome do login a excluir" || return
    local uname="$REPLY_VALUE"
    input::confirm "Confirma exclusão do login '$uname'?" || { ui::info "Cancelado."; return; }
    if sqlserver_exec "DROP LOGIN [$uname];" >/dev/null; then
        ui::ok "Login '$uname' excluído."
    else
        ui::error "Falha ao excluir login."
    fi
}

sqlserver_restore() {
    input::choose_backup_file sqlserver bak || return
    local file="$REPLY_FILE"
    printf '\n'
    ui::info "Arquivos lógicos dentro do backup (necessários para MOVE):"
    ui::hr
    sqlserver_exec "RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/$file';"
    ui::hr
    printf '\n'
    input::read_required "Nome do banco destino" || return
    local dbname="$REPLY_VALUE"
    local mdf_name ldf_name
    input::read_required "Nome lógico do arquivo MDF (da lista acima)" || return
    mdf_name="$REPLY_VALUE"
    input::read_required "Nome lógico do arquivo LDF (da lista acima)" || return
    ldf_name="$REPLY_VALUE"

    ui::info "Restaurando '$file' como '$dbname'..."
    sqlserver_exec "RESTORE DATABASE [$dbname]
FROM DISK = N'/var/opt/mssql/backup/$file'
WITH REPLACE,
     MOVE '$mdf_name' TO '/var/opt/mssql/data/${dbname}.mdf',
     MOVE '$ldf_name' TO '/var/opt/mssql/data/${dbname}_log.ldf';" 2>&1
    ui::ok "Restauração de '$file' concluída."
}
