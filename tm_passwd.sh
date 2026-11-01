#!/usr/bin/env bash
# Définit le mot de passe root ET le mémorise dans /data/ssh/root.shadow (sous forme de hash)
# pour qu'il soit réappliqué à chaque démarrage, y compris après recréation du CT.
# Usage : tm-passwd   (à lancer dans le conteneur, par exemple via `pct enter ID`)
set -euo pipefail

DATA="${DATA_DIR:-/data}"

passwd root

hash="$(getent shadow root | cut -d: -f2)"
case "$hash" in
  ''|'*'|'!'*)
    echo "Aucun mot de passe valide enregistré, rien n'a été mémorisé." >&2
    exit 1
    ;;
esac

mkdir -p "$DATA/ssh"
chmod 700 "$DATA/ssh"
umask 077
printf '%s\n' "$hash" > "$DATA/ssh/root.shadow"
echo "Mot de passe mémorisé dans $DATA/ssh/root.shadow : il sera conservé si le CT est recréé."
