# tm-aio : serveur Trackmania 2020 pour Proxmox

Image OCI « tout-en-un » : serveur dédié Trackmania 2020 + PyPlanet + MariaDB, dans un seul conteneur.

**Le but est simple : récupérer l'image OCI sur Proxmox, créer un conteneur, et c'est tout.**
Cette image est faite avant tout pour mon usage perso, avec mes réglages par défaut. Elle peut servir
à d'autres, mais elle n'est ni générique ni supportée.

## Utilisation sur Proxmox (9.1 ou plus)

1. Stockage → **CT Templates** → **Pull from OCI Registry**
   - Image : `ghcr.io/teilenh/tm-aio`
   - Tag : `latest`
2. Créer un conteneur à partir de ce template :
   - non privilégié (pas besoin de nesting)
   - 2 vCPU, 2 Go de RAM, 512 Mo de swap, 6 à 8 Go de disque
   - un **point de montage** sur `/data` (10 Go, volume géré par Proxmox) : c'est là que sont les
     maps, la config, la base de données et les classements
3. Démarrer. **Il n'y a rien à configurer.**

Joueurs : ils rejoignent le serveur par l'IP du conteneur (port 2350, TCP et UDP), via le réseau local
ou le VPN.

## Réglages par défaut

- **Mode LAN** (`/lan`) : aucun compte serveur Trackmania requis.
- **Propriétaire PyPlanet** : `Teilen`.
- **10 joueurs** maximum.
- **Maps** : au premier lancement, les Weekly Shorts du moment sont téléchargées et mises en rotation
  (Time Attack, 10 minutes par map).
- **PyPlanet** : records locaux, jukebox (vote de la prochaine map), karma, ajout de maps depuis
  ManiaExchange.
- Tout ce qui doit survivre est dans `/data` : recréer le conteneur avec une nouvelle image ne perd rien.

## Changer quelque chose (optionnel)

Variables d'environnement du conteneur (à définir dans les options du CT, selon ta version de Proxmox) :

| Variable | Rôle |
|---|---|
| `PP_OWNERS` | Login(s) propriétaires PyPlanet, séparés par des virgules (défaut : `Teilen`) |
| `TM_SERVER_NAME` | Nom du serveur |
| `TM_MAX_PLAYERS` | Nombre de joueurs (défaut : 10) |
| `TM_PASSWORD`, `TM_SPECTATOR_PASSWORD` | Mots de passe joueurs / spectateurs |
| `TM_MASTER_LOGIN`, `TM_MASTER_PASSWORD` | Compte serveur dédié : passe en mode en ligne |
| `TM_LAN` | `1` = LAN, `0` = en ligne (par défaut : LAN si pas de `TM_MASTER_LOGIN`) |
| `TM_FORCE_IP` | IP annoncée par le serveur, si c'est la mauvaise |
| `TM_EXTRA_ARGS` | Options supplémentaires passées à `TrackmaniaServer` |

Contenu de `/data` :

- `UserData/` : config du serveur, `Maps/` (tes `.Map.Gbx`), `Maps/MatchSettings/tracklist.txt` (la rotation)
- `mysql/` : base de données (classements PyPlanet)
- `pyplanet/` : projet PyPlanet, `settings/base.py` modifiable (généré une seule fois)
- `secrets/` : mots de passe internes générés

Si je ne suis pas admin dans le jeu : PyPlanet identifie les propriétaires par **login**, pas par pseudo.
Relever le login dans les logs à la connexion, puis le mettre dans `OWNERS` de
`/data/pyplanet/settings/base.py`.

## Construire / tester soi-même

L'image est construite par GitHub Actions (Buildah) et poussée sur GHCR, avec un rebuild hebdomadaire
pour récupérer la dernière version du serveur Nadeo.

    podman build -t localhost/tm-aio:latest -f Containerfile .
    podman run --rm -it --cgroups=disabled -v tm-data:/data \
      -p 2350:2350/tcp -p 2350:2350/udp localhost/tm-aio:latest

(`--cgroups=disabled` est utile pour Podman sans session systemd complète.)

## À savoir

- Python 3.9 (PyPlanet ne s'installe pas en 3.10+ ; 3.8 en repli via `--build-arg PYTHON_TAG=3.8-slim-bookworm`).
- Le serveur Nadeo est téléchargé au build : reconstruire l'image pour le mettre à jour.
- Les ports XML-RPC (5000) et MariaDB (3306) restent internes au conteneur.
- Pour des joueurs derrière un VPN, la découverte « Local network » du jeu peut ne pas traverser le
  VPN : utiliser alors le Join Link avec l'IP du serveur (non vérifié).
