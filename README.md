# dbm — Docker DB Manager

Gerenciador interativo de containers Docker para os principais bancos de dados de desenvolvimento.
Um dashboard estilo `lazydocker`, escrito em Bash puro, para subir, parar, conectar e inspecionar
**PostgreSQL**, **MySQL**, **Oracle Free** e **SQL Server** sem precisar lembrar de um único `docker run`.

```
  ╔══════════════════════════════════╗
  ║          DB Manager Docker       ║
  ╚══════════════════════════════════╝
   BANCO         STATUS        CPU      MEM         PORTA    CONTAINER
 ▶ postgres      ● rodando     0.4%     54MB        :5432    postgres-dev
   mysql         ● rodando     1.1%     412MB       :3306    mysql-dev
   oracle        ■ parado       —        —          :1521    oracle-dev
   sqlserver     ○ ausente      —        —          :1433    sqlserver-dev
```

---

## ✨ Features

- 🎛️  **Dashboard interativo** com auto-refresh, navegação single-key (estilo `lazydocker`/`k9s`).
- 🚀 **CLI direta** para scripts: `dbm start postgres`, `dbm logs mysql 100`, `dbm exec oracle`.
- 📦 **4 SGBDs prontos:** PostgreSQL 16, MySQL 8, Oracle 23ai Free, SQL Server 2022.
- 🔌 **Conexão one-shot** ao cliente do banco (psql, mysql, sqlplus, sqlcmd) sem instalar nada local.
- 📊 **Stats em tempo real:** CPU/MEM por container, status, portas, nomes.
- 💾 **Backup & restore** integrados em `backups/<banco>/`.
- 🧩 **Extensível:** adicionar um novo SGBD = criar um arquivo em `databases/<nome>.sh`.
- ⚙️  **Config opcional** em `~/.config/dbm/config.sh` (portas, senhas, imagens).
- 🪶 **Zero dependências** além de Bash 4+ e Docker. Sem Python, sem Node, sem Go.

---

## 📦 Instalação

### Pré-requisitos

- Linux (testado no Ubuntu 22.04+).
- Docker Engine ou Docker Desktop ([guia oficial](https://docs.docker.com/engine/install/ubuntu/)).
- Bash 4 ou superior.

Verifique se o Docker está pronto:

```bash
docker --version
docker run hello-world
```

### Clonar e instalar

```bash
git clone https://github.com/joaquimoiio/docker-db-manager.git ~/docker
cd ~/docker
chmod +x dbm db-manager.sh
```

Opcional — adicione ao `PATH` para chamar `dbm` de qualquer lugar:

```bash
echo 'export PATH="$HOME/docker:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 🚀 Uso

### Dashboard interativo (modo padrão)

```bash
dbm
```

Navegue com `↑/↓`, ações com uma tecla:

| Tecla | Ação                              |
|-------|-----------------------------------|
| `s`   | Start container                   |
| `x`   | Stop                              |
| `r`   | Restart                           |
| `d`   | Delete (destrutivo, pede confirmação) |
| `l`   | Logs (tail)                       |
| `f`   | Follow logs (Ctrl-C sai)          |
| `e`   | Abrir cliente do banco            |
| `m`   | Menu de gerenciamento (databases, users, restore) |
| `q`   | Sair                              |

### CLI direta (sem UI)

```bash
dbm start postgres          # sobe o container
dbm stop mysql              # para
dbm restart oracle
dbm delete sqlserver        # remove (pede confirmação)
dbm logs postgres 100       # últimas 100 linhas
dbm follow mysql            # logs em tempo real
dbm exec postgres           # abre psql no container

dbm status                  # tabela snapshot de todos
dbm stats                   # CPU/MEM dos containers
dbm volumes
dbm networks
dbm help
```

---

## 🔐 Credenciais padrão

> ⚠️  **Apenas para desenvolvimento local.** Para alterar, copie `etc/config.sh.example` para
> `~/.config/dbm/config.sh` e edite — o arquivo nunca é versionado.

| SGBD       | Host      | Porta | Usuário  | Senha           | Banco/SID |
|------------|-----------|-------|----------|-----------------|-----------|
| PostgreSQL | localhost | 5432  | postgres | postgres        | devdb     |
| MySQL      | localhost | 3306  | root     | Root@123        | devdb     |
| Oracle Free| localhost | 1521  | system   | oracle          | FREEPDB1  |
| SQL Server | localhost | 1433  | sa       | SqlServer\@123  | —         |

> Oracle leva ~60s para inicializar; SQL Server ~30s.

### Conectar com cliente gráfico (DBeaver, TablePlus, etc.)

Use as credenciais da tabela acima — todos os containers expõem `localhost:<porta>`.

### Conectar pelo terminal sem cliente local

```bash
dbm exec postgres   # abre psql -U postgres -d devdb
dbm exec mysql      # abre mysql -u root -p... devdb
dbm exec oracle     # abre sqlplus system/oracle@FREEPDB1
dbm exec sqlserver  # abre sqlcmd -S localhost -U sa
```

---

## 🗂️  Estrutura do projeto

```
docker/
├── dbm                   # entrypoint principal
├── db-manager.sh         # shim de compatibilidade (alias antigo)
├── lib/                  # núcleo: UI, lifecycle, docker, logs, stats, ...
│   ├── core.sh
│   ├── theme.sh
│   ├── ui.sh
│   ├── input.sh
│   ├── docker.sh
│   ├── lifecycle.sh
│   ├── logs.sh
│   ├── stats.sh
│   ├── volumes.sh
│   ├── networks.sh
│   ├── manage.sh
│   └── dashboard.sh
├── databases/            # um módulo por SGBD
│   ├── _common.sh
│   ├── postgres.sh
│   ├── mysql.sh
│   ├── oracle.sh
│   └── sqlserver.sh
├── etc/
│   └── config.sh.example # template de overrides
└── backups/<banco>/      # dumps gerados pelo menu de manage
```

---

## ➕ Adicionar um novo SGBD

1. Criar `databases/<nome>.sh` seguindo o contrato dos módulos existentes
   (`<db>_create_container`, `<db>_show_credentials`, `<db>_shell_cmd`,
   `<db>_list_databases`, ...).
2. Adicionar `<nome>` no array `DB_TYPES` em `dbm`.
3. (Opcional) adicionar defaults em `etc/config.sh.example`.

---

## 🧰 Resolução de problemas

**"Cannot connect to the Docker daemon"** → Docker não está rodando.
```bash
sudo systemctl start docker
```

**"port is already allocated"** → algo já ocupa a porta. Identifique e pare:
```bash
sudo lsof -i :5432
sudo systemctl stop postgresql   # se for o postgres do sistema
```

**Banco demora para responder após start** → Oracle/SQL Server precisam de ~30–60s.
Use `dbm follow <banco>` para acompanhar a inicialização.

**"permission denied" ao rodar `dbm`** → falta o bit de execução:
```bash
chmod +x ~/docker/dbm
```

**Perdi os dados ao deletar o container** → `delete` remove o container e seus dados.
Para preservar entre remoções, configure volumes Docker.

---

## 🤝 Contribuindo

PRs são bem-vindos. Sugestões úteis:

- Novos SGBDs (MariaDB, MongoDB, Redis, etc.).
- Suporte a volumes nomeados persistentes.
- Profiles (`dbm --profile work start postgres`).
- Tradução do dashboard.

Abra uma issue antes de mudanças grandes para alinhar a abordagem.

---

## 📄 Licença

MIT — veja [`LICENSE`](LICENSE).
