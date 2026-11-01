#!/usr/bin/env bash
# Lance sshd (toujours actif). Connexion en root, par mot de passe ou par clé.
#
# Le compte root n'a AUCUN mot de passe valide au départ : personne ne peut se connecter tant que tu n'en
# as pas défini un (commande `tm-passwd`, depuis `pct enter ID`). Le mot de passe est mémorisé (sous forme
# de hash) dans /data/ssh/root.shadow et réappliqué à chaque démarrage, donc il survit à la recréation du CT.
# Optionnel : clés publiques via SSH_PUBKEY et/ou /data/ssh/authorized_keys.
# Les clés d'hôte sont dans /data/ssh : l'empreinte ne change pas quand le CT est recréé.
set -euo pipefail

DATA="${DATA_DIR:-/data}"
RHOME="${SSH_ROOT_HOME:-/root}"
SSHD="${SSHD:-/usr/sbin/sshd}"
USERMOD="${USERMOD:-usermod}"

mkdir -p "$DATA/ssh"
chmod 700 "$DATA/ssh"

# Mot de passe root mémorisé (hash), réappliqué au démarrage
if [ -s "$DATA/ssh/root.shadow" ]; then
  "$USERMOD" -p "$(cat "$DATA/ssh/root.shadow")" root
  echo "[ssh] mot de passe root restauré depuis $DATA/ssh/root.shadow."
else
  echo "[ssh] aucun mot de passe root défini : lance « tm-passwd » (pct enter ID) pour pouvoir te connecter."
fi

# Clés publiques (facultatif)
install -d -m 700 "$RHOME/.ssh"
keys="$RHOME/.ssh/authorized_keys"
: > "$keys"
if [ -n "${SSH_PUBKEY:-}" ]; then
  printf '%s\n' "$SSH_PUBKEY" >> "$keys"
fi
if [ -s "$DATA/ssh/authorized_keys" ]; then
  cat "$DATA/ssh/authorized_keys" >> "$keys"
fi
chmod 600 "$keys"

hostkey="$DATA/ssh/ssh_host_ed25519_key"
if [ ! -f "$hostkey" ]; then
  ssh-keygen -q -t ed25519 -N '' -f "$hostkey"
fi

mkdir -p /run/sshd
echo "[ssh] sshd démarré (root, mot de passe ou clé)."
exec "$SSHD" -D -e -h "$hostkey" \
  -o PermitRootLogin=yes \
  -o PasswordAuthentication=yes \
  -o PermitEmptyPasswords=no \
  -o KbdInteractiveAuthentication=no
