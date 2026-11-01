#!/usr/bin/env python3
"""Génère/ajuste dedicated_cfg.txt et les réglages PyPlanet à partir des variables d'environnement.

Usage : configure.py dedicated | pyplanet
Les valeurs sont appliquées à chaque démarrage pour dedicated_cfg.txt (seules les variables
définies écrasent le fichier). Les réglages PyPlanet ne sont générés qu'une fois.
"""
import os
import sys
import shutil
import xml.etree.ElementTree as ET

DATA = os.environ.get("DATA_DIR", "/data")
CFG_DIR = os.path.join(DATA, "UserData", "Config")
CFG = os.path.join(CFG_DIR, "dedicated_cfg.txt")
CFG_DEFAULT = os.path.join(CFG_DIR, "dedicated_cfg.default.txt")


def set_text(root, path, value):
    """Met à jour (ou crée) un élément XML via un chemin 'a/b/c'."""
    node = root
    for part in path.split("/"):
        child = node.find(part)
        if child is None:
            child = ET.SubElement(node, part)
        node = child
    node.text = str(value)


def configure_dedicated():
    if not os.path.exists(CFG):
        shutil.copy(CFG_DEFAULT, CFG)
    tree = ET.parse(CFG)
    root = tree.getroot()

    set_text(root, "masterserver_account/login", os.environ["TM_MASTER_LOGIN"])
    set_text(root, "masterserver_account/password", os.environ["TM_MASTER_PASSWORD"])
    set_text(root, "server_options/max_players", os.environ.get("TM_MAX_PLAYERS", "10"))

    optional = {
        "TM_SERVER_NAME": "server_options/name",
        "TM_SERVER_COMMENT": "server_options/comment",
        "TM_PASSWORD": "server_options/password",
        "TM_SPECTATOR_PASSWORD": "server_options/password_spectator",
        "TM_FORCE_IP": "system_config/force_ip_address",
    }
    for env, path in optional.items():
        if os.environ.get(env):
            set_text(root, path, os.environ[env])

    # Ports : jeu 2350, P2P 3450, XML-RPC 5000 (local uniquement, le contrôleur est dans le même conteneur)
    set_text(root, "system_config/server_port", "2350")
    set_text(root, "system_config/server_p2p_port", "3450")
    set_text(root, "system_config/xmlrpc_port", "5000")
    set_text(root, "system_config/xmlrpc_allowremote", "False")

    # Mot de passe SuperAdmin (utilisé par PyPlanet via XML-RPC)
    for level in root.findall("authorization_levels/level"):
        if (level.findtext("name") or "") == "SuperAdmin":
            pw = level.find("password")
            if pw is None:
                pw = ET.SubElement(level, "password")
            pw.text = os.environ["XMLRPC_PASSWORD"]

    tree.write(CFG, encoding="utf-8", xml_declaration=True)


PYPLANET_SETTINGS = '''# Fichier généré au premier lancement par configure.py. Tu peux le modifier librement :
# il ne sera plus réécrit (supprime .settings_generated pour le régénérer).
# Clés selon la doc PyPlanet : vérifie-les si ta version diffère.
import os

DEBUG = False

DATABASES = {{
    'default': {{
        'ENGINE': 'peewee_async.MySQLDatabase',
        'NAME': 'pyplanet',
        'OPTIONS': {{
            'host': '127.0.0.1',
            'user': 'pyplanet',
            'password': {db_password!r},
        }}
    }},
}}

DEDICATED = {{
    'default': {{
        'HOST': '127.0.0.1',
        'PORT': 5000,
        'USER': 'SuperAdmin',
        'PASSWORD': {xmlrpc_password!r},
    }},
}}

MAP_MATCHSETTINGS = {{
    'default': 'tracklist.txt',
}}

OWNERS = {{
    'default': {owners!r},
}}
'''


def configure_pyplanet():
    base = os.path.join(DATA, "pyplanet")
    marker = os.path.join(base, ".settings_generated")
    if os.path.exists(marker):
        return
    owners = [o.strip() for o in os.environ["PP_OWNERS"].split(",") if o.strip()]
    content = PYPLANET_SETTINGS.format(
        db_password=os.environ["DB_PASSWORD"],
        xmlrpc_password=os.environ["XMLRPC_PASSWORD"],
        owners=owners,
    )
    with open(os.path.join(base, "settings", "base.py"), "w", encoding="utf-8") as f:
        f.write(content)
    open(marker, "w").close()


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "dedicated":
        configure_dedicated()
    elif mode == "pyplanet":
        configure_pyplanet()
    else:
        sys.exit("usage: configure.py dedicated|pyplanet")
