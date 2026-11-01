#!/usr/bin/env bash
set -euo pipefail

# Propriétaire(s) PyPlanet (logins séparés par des virgules). Par défaut : Teilen.
export PP_OWNERS="${PP_OWNERS:-Teilen}"

# Mode LAN (option /lan du serveur, sans compte masterserver) :
#  - TM_LAN=1 force le mode LAN, TM_LAN=0 force le mode en ligne ;
#  - non défini : LAN si TM_MASTER_LOGIN est absent, en ligne sinon.
if [ -z "${TM_LAN:-}" ]; then
  if [ -n "${TM_MASTER_LOGIN:-}" ]; then TM_LAN=0; else TM_LAN=1; fi
fi
if [ "$TM_LAN" != "1" ]; then
  : "${TM_MASTER_LOGIN:?Mode en ligne : définis TM_MASTER_LOGIN (compte serveur dédié) ou utilise TM_LAN=1}"
  : "${TM_MASTER_PASSWORD:?Mode en ligne : définis TM_MASTER_PASSWORD}"
fi
export TM_LAN
if [ "$TM_LAN" = "1" ]; then export TM_LAN_ARGS="/lan"; else export TM_LAN_ARGS=""; fi
export TM_EXTRA_ARGS="${TM_EXTRA_ARGS:-}"   # options supplémentaires passées au serveur

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

# Liste de maps par défaut si aucune n'existe : on télécharge les Weekly Shorts (comme ton
# setup_server.py) et on génère tracklist.txt ; repli sur l'exemple du serveur si ça échoue.
MS="$DATA/UserData/Maps/MatchSettings"
mkdir -p "$MS"
if [ ! -e "$MS/tracklist.txt" ]; then
  python3 /usr/local/bin/bootstrap_maps.py "$DATA/UserData" || true
fi
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
# Tant que le marqueur .settings_v2 est absent, on repart du modèle propre de PyPlanet,
# puis configure.py y ajoute nos réglages (et crée le marqueur).
if [ ! -f "$DATA/pyplanet/.settings_v2" ]; then
  tmp="$(mktemp -d)"
  (cd "$tmp" && pyplanet init_project proj)
  cp -a "$tmp/proj/." "$DATA/pyplanet/"
  rm -rf "$tmp"
fi
python3 /usr/local/bin/configure.py pyplanet

chown -R tm:tm "$DATA/UserData" "$DATA/pyplanet"

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
