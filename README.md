# Trackmania 2020 AIO (Podman / OCI)

Un seul conteneur : serveur dédié Trackmania 2020 + PyPlanet + MariaDB, supervisés par supervisord.
Base Debian bookworm (glibc native). Non testé : voir « À vérifier » en bas.

## Build

    podman build -t localhost/tm-aio:latest -f Containerfile .

Options : `--build-arg PYTHON_TAG=3.8-slim-bookworm` (défaut : 3.9, PyPlanet ne s'installe pas en 3.10+),
`--build-arg PYPLANET_SPEC="pyplanet==x.y.z"`.
Le serveur Nadeo est téléchargé au build : reconstruis l'image pour le mettre à jour.

## Lancer avec Podman

    podman run -d --name tm \
      -e TM_MASTER_LOGIN='ton_login_serveur' \
      -e TM_MASTER_PASSWORD='ton_mdp_serveur' \
      -e PP_OWNERS='ton_login_trackmania' \
      -e TM_SERVER_NAME='Notre serveur' \
      -e TM_MAX_PLAYERS=10 \
      -p 2350:2350/tcp -p 2350:2350/udp \
      -p 3450:3450/tcp -p 3450:3450/udp \
      -v tm-data:/data \
      localhost/tm-aio:latest

Logs : `podman logs -f tm`.

## Variables d'environnement

| Variable | Obligatoire | Rôle |
|---|---|---|
| `TM_MASTER_LOGIN` / `TM_MASTER_PASSWORD` | oui | Compte serveur dédié (site Trackmania) |
| `PP_OWNERS` | oui | Login(s) propriétaires PyPlanet, séparés par des virgules |
| `TM_SERVER_NAME`, `TM_SERVER_COMMENT` | non | Nom et description |
| `TM_MAX_PLAYERS` | non | Défaut 10 |
| `TM_PASSWORD`, `TM_SPECTATOR_PASSWORD` | non | Mots de passe joueurs / spectateurs |
| `TM_FORCE_IP` | non | IP publique si le serveur s'annonce avec la mauvaise |
| `TM_XMLRPC_PASSWORD` | non | Sinon généré et stocké dans `/data/secrets` |

## Volume `/data`

- `UserData/` : config du serveur, `Maps/` (tes `.Map.Gbx`), `Maps/MatchSettings/tracklist.txt` (rotation)
- `mysql/` : base de données (classements PyPlanet)
- `pyplanet/` : projet PyPlanet, `settings/base.py` modifiable (généré une fois)
- `secrets/` : mots de passe générés

`dedicated_cfg.txt` est ré-appliqué à chaque démarrage avec les variables définies.
Les réglages PyPlanet ne sont générés qu'une fois ; supprime `pyplanet/.settings_generated` pour les régénérer.

## Proxmox (OCI natif, PVE 9.1+)

    podman save --format oci-archive -o tm-aio.tar localhost/tm-aio:latest

Importe `tm-aio.tar` comme template de conteneur (ou pousse l'image dans un registre et utilise
« Pull from OCI Registry »), puis crée le CT avec un point de montage sur `/data`.
Prévois 2 vCPU, 2 Go de RAM, 15–20 Go de disque. Redirige 2350 (TCP+UDP) vers l'IP du CT.

## À vérifier au premier lancement (non testé ici)

- Compatibilité de PyPlanet avec Python 3.9 (3.8 en repli via `PYTHON_TAG`).
- Noms des clés de `settings/base.py` PyPlanet selon ta version.
- Noms des éléments XML de `dedicated_cfg.default.txt` (`configure.py` crée les éléments manquants).
- Option `/nodaemon` du serveur et mode de jeu de `tracklist.txt`.
- Adresse du zip serveur (`SERVER_ZIP`) toujours valide.
