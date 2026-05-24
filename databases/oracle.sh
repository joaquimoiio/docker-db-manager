#!/usr/bin/env bash
# Módulo Oracle XE — única instância (SID=XE), schema = banco.

ORACLE_LABEL="Oracle XE"
ORACLE_TAGLINE="schema-based · PL/SQL · enterprise · XE 21c"
ORACLE_CONTAINER="oracle-dev"
ORACLE_IMAGE="${DBM_ORACLE_IMAGE:-gvenzl/oracle-xe:21}"
ORACLE_PORT="${DBM_ORACLE_PORT:-1521}"
ORACLE_PASSWORD="${DBM_ORACLE_PASSWORD:-oracle}"

oracle_create_container() {
    docker run -d \
        --name "$ORACLE_CONTAINER" \
        -e ORACLE_PASSWORD="$ORACLE_PASSWORD" \
        -p "${ORACLE_PORT}:1521" \
        -v "$DBM_BACKUP_DIR/oracle:/backups" \
        --restart unless-stopped \
        "$ORACLE_IMAGE" >/dev/null
}

oracle_show_credentials() {
    ui::panel_row "usuário" "system"
    ui::panel_row "senha"   "$ORACLE_PASSWORD"
    ui::panel_row "SID"     "XE"
}

oracle_shell_cmd() {
    docker exec -it "$ORACLE_CONTAINER" \
        sqlplus system/"$ORACLE_PASSWORD"@XE
}

oracle_start_note() {
    ui::warn "Aguarde ~60s para o Oracle inicializar completamente."
}

oracle_manage_note() {
    printf '  %s%s%s %s%sOracle XE: usuário = schema. Criar usuário = criar banco.%s\n' \
        "$BOLD$CLR_WARN" "$GLYPH_WARN" "$NC" "$ITALIC" "$CLR_FG" "$NC"
}

oracle_exec() {
    docker exec "$ORACLE_CONTAINER" \
        sqlplus -S system/"$ORACLE_PASSWORD"@XE <<< "
SET PAGESIZE 50
SET LINESIZE 120
SET FEEDBACK OFF
$1
EXIT
" 2>&1
}

oracle_setup_backup_dir() {
    oracle_exec "CREATE OR REPLACE DIRECTORY BACKUP_DIR AS '/backups';
GRANT READ, WRITE ON DIRECTORY BACKUP_DIR TO SYSTEM;" >/dev/null
}

oracle_list_databases() {
    local excluded="'SYS','SYSTEM','DBSNMP','APPQOSSYS','AUDSYS','CTXSYS','DVSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMROOTUSER','GSMUSER','LBACSYS','MDSYS','OJVMSYS','OLAPSYS','OUTLN','WMSYS','XDB'"
    ui::info "Schemas de usuário no Oracle XE:"
    ui::hr
    oracle_exec "SELECT username, account_status, TO_CHAR(created,'DD/MM/YYYY') AS created
FROM dba_users
WHERE username NOT IN ($excluded)
ORDER BY username;"
    ui::hr
}

oracle_create_database() {
    ui::info "No Oracle XE, criar um banco = criar um schema/usuário."
    printf '\n'
    input::read_required "Nome do schema (usuário)" || return
    local uname="$REPLY_VALUE"
    input::read_required "Senha" secret || return
    local upass="$REPLY_VALUE"
    if oracle_exec "CREATE USER \"$uname\" IDENTIFIED BY \"$upass\";
GRANT CONNECT, RESOURCE, CREATE SESSION TO \"$uname\";
ALTER USER \"$uname\" QUOTA UNLIMITED ON USERS;" >/dev/null; then
        ui::ok "Schema '$uname' criado."
    else
        ui::error "Falha ao criar schema."
    fi
}

oracle_drop_database() {
    oracle_list_databases
    printf '\n'
    ui::warn "Excluir um schema remove TODOS os seus objetos (CASCADE)."
    input::read_required "Nome do schema a excluir" || return
    local uname="$REPLY_VALUE"
    input::confirm "Confirma exclusão de '$uname'?" || { ui::info "Cancelado."; return; }
    if oracle_exec "DROP USER \"$uname\" CASCADE;" >/dev/null; then
        ui::ok "Schema '$uname' excluído."
    else
        ui::error "Falha ao excluir schema."
    fi
}

oracle_list_users()  { oracle_list_databases; }
oracle_create_user() { oracle_create_database; }
oracle_drop_user()   { oracle_drop_database; }

oracle_restore() {
    input::choose_backup_file oracle dmp || return
    local file="$REPLY_FILE"
    local src_schema dst_schema
    input::read_required "Schema de origem no backup" || return
    src_schema="$REPLY_VALUE"
    input::read_optional "Schema destino" "$src_schema"
    dst_schema="$REPLY_VALUE"

    ui::info "Configurando diretório de backup no Oracle..."
    oracle_setup_backup_dir
    ui::info "Executando impdp — pode demorar alguns minutos..."
    docker exec "$ORACLE_CONTAINER" \
        impdp system/"$ORACLE_PASSWORD"@XE \
        DIRECTORY=BACKUP_DIR \
        DUMPFILE="$file" \
        REMAP_SCHEMA="${src_schema}:${dst_schema}" \
        LOGFILE=impdp_restore.log 2>&1
    ui::ok "Restauração concluída. Log: $DBM_BACKUP_DIR/oracle/impdp_restore.log"
}
