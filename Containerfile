# Trackmania 2020 AIO : serveur dédié + PyPlanet + MariaDB (supervisés par supervisord)
# Build : podman build -t localhost/tm-aio:latest -f Containerfile .
#
# Base Debian (glibc native) : pas besoin de couche de compatibilité glibc comme sur Alpine.
# PyPlanet fige d'anciennes dépendances qui ne tournent pas au-delà de Python 3.8 :
#  - peewee==2.10.2 fait `from collections import Callable` (supprimé en 3.10) ;
#  - peewee-async==0.5.12 appelle asyncio.Task.current_task (supprimé en 3.9).
ARG PYTHON_TAG=3.8-slim-bookworm
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
      mariadb-server supervisor openssh-server ca-certificates wget unzip tzdata \
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
COPY bootstrap_maps.py /usr/local/bin/bootstrap_maps.py
# Chemin par défaut de supervisord : `supervisorctl` fonctionne ainsi sans option -c
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY run_sshd.sh /usr/local/bin/run-sshd.sh
COPY tm_passwd.sh /usr/local/bin/tm-passwd
# pam_loginuid échoue dans un LXC non privilégié et bloque la connexion SSH : on le rend optionnel
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/run-sshd.sh /usr/local/bin/tm-passwd \
 && sed -i 's/^session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/sshd

# 2350 : jeu (TCP+UDP) ; 3450 : P2P ; 22 : SSH (root ; mot de passe défini avec tm-passwd, ou clé).
# XML-RPC (5000) et MariaDB (3306) restent internes.
EXPOSE 2350/tcp 2350/udp 3450/tcp 3450/udp 22/tcp

# Tout l'état persistant (maps, config, base de données, secrets) vit ici.
VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
