# Trackmania 2020 AIO : serveur dédié + PyPlanet + MariaDB (supervisés par supervisord)
# Build : podman build -t localhost/tm-aio:latest -f Containerfile .
#
# Base Debian (glibc native) : pas besoin de couche de compatibilité glibc comme sur Alpine.
# PyPlanet fige d'anciennes dépendances (peewee==2.10.2) qui font `from collections import Callable`,
# supprimé en Python 3.10 : il faut Python <= 3.9. Si 3.9 pose encore problème, essaie 3.8
# (--build-arg PYTHON_TAG=3.8-slim-bookworm), qui correspond aux classifiers de PyPlanet.
ARG PYTHON_TAG=3.9-slim-bookworm
FROM docker.io/library/python:${PYTHON_TAG}

ARG SERVER_ZIP=http://files.v04.maniaplanet.com/server/TrackmaniaServer_Latest.zip
# Pour figer une version : --build-arg PYPLANET_SPEC="pyplanet==x.y.z"
ARG PYPLANET_SPEC=pyplanet

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    TM_DIR=/opt/trackmania \
    DATA_DIR=/data

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      mariadb-server supervisor ca-certificates wget unzip tzdata \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --system --home-dir /opt/trackmania --shell /usr/sbin/nologin tm

# pip à jour d'abord. pymysql et cryptography sont déjà imposés par PyPlanet (ne pas les forcer ici,
# ça crée des conflits de versions) ; aiomysql est le pilote MySQL/MariaDB utilisé via peewee-async.
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir ${PYPLANET_SPEC} aiomysql

# Le serveur est téléchargé à la construction : reconstruis l'image pour le mettre à jour.
RUN mkdir -p ${TM_DIR} \
 && wget -q -O /tmp/server.zip "${SERVER_ZIP}" \
 && unzip -q /tmp/server.zip -d ${TM_DIR} \
 && rm /tmp/server.zip \
 && chmod +x ${TM_DIR}/TrackmaniaServer \
 && mv ${TM_DIR}/UserData ${TM_DIR}/UserData.default \
 && chown -R tm:tm ${TM_DIR}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY configure.py  /usr/local/bin/configure.py
COPY supervisord.conf /etc/supervisor/tm.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

# 2350 : jeu (TCP+UDP) ; 3450 : P2P. XML-RPC (5000) et MariaDB (3306) restent internes.
EXPOSE 2350/tcp 2350/udp 3450/tcp 3450/udp

# Tout l'état persistant (maps, config, base de données, secrets) vit ici.
VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
