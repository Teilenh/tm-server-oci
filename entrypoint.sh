#!/usr/bin/env bash
set -euo pipefail

: "${TM_MASTER_LOGIN:?Définis TM_MASTER_LOGIN (login du compte serveur dédié Trackmania)}"
: "${TM_MASTER_PASSWORD:?Définis TM_MASTER_PASSWORD}"
: "${PP_OWNERS:?Définis PP_OWNERS (ton login Ubisoft/Trackmania, séparés par des virgules)}"

DATA="${DATA_DIR:-/data}"
TM="${TM_DIR:-/opt/trackmania}"
DB_NAME=pyplanet
DB_USER=pyplanet

mkdir -p "$DATA"/{UserData,mysql,pyplanet,secrets}
chmod 700 "$DATA/secrets"

# Secrets générés une fois et conservés dans le volume
secret() {
  local f="$DATA/secrets/$1"
  [ -s "$f" ] || python3 -c 'import secrets;print(secrets.token_hex(16))' > "$f"
  cat "$f"
}
export DB_PASSWORD="$(secret db_password)"
export XMLRPC_PASSWORD="${TM_XMLRPC_PASSWORD:-$(secret xmlrpc_password)}"

# --- UserData du serveur : copie des défauts au premier lancement ---
if [ ! -e "$DATA/UserData/.initialized" ]; then
  cp -a "$TM/UserData.default/." "$DATA/UserData/"
  touch "$DATA/UserData/.initialized"
fi
ln -sfn "$DATA/UserData" "$TM/UserData"

# Liste de maps par défaut si aucune n'existe
MS="$DATA/UserData/Maps/MatchSettings"
mkdir -p "$MS"
if [ ! -e "$MS/tracklist.txt" ] && [ -e "$MS/example.txt" ]; then
  cp "$MS/example.txt" "$MS/tracklist.txt"
fi

# --- dedicated_cfg.txt : applique les variables d'environnement ---
python3 /usr/local/bin/configure.py dedicated

# --- MariaDB : init au premier lancement, puis création base/utilisateur (idempotent) ---
mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld "$DATA/mysql"
if [ ! -d "$DATA/mysql/mysql" ]; then
  mariadb-install-db --user=mysql --datadir="$DATA/mysql" --skip-test-db >/dev/null
fi

SOCK=/run/mysqld/init.sock
mariadbd --user=mysql --datadir="$DATA/mysql" --skip-networking --socket="$SOCK" &
init_pid=$!
for _ in $(seq 1 60); do
  mariadb --socket="$SOCK" -e 'SELECT 1' >/dev/null 2>&1 && break
  sleep 1
done
mariadb --socket="$SOCK" <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
ALTER USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL
mariadb-admin --socket="$SOCK" shutdown
wait "$init_pid" || true

# --- Projet PyPlanet : créé au premier lancement, réglages générés une seule fois ---
if [ ! -f "$DATA/pyplanet/manage.py" ]; then
  tmp="$(mktemp -d)"
  (cd "$tmp" && pyplanet init_project proj)
  cp -a "$tmp/proj/." "$DATA/pyplanet/"
  rm -rf "$tmp"
fi
python3 /usr/local/bin/configure.py pyplanet

chown -R tm:tm "$DATA/UserData" "$DATA/pyplanet"

exec /usr/bin/supervisord -n -c /etc/supervisor/tm.conf
