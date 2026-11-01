#!/usr/bin/env python3
"""Génère les réglages du serveur et du projet PyPlanet au démarrage."""

import argparse
import os
from pathlib import Path
import xml.etree.ElementTree as ET


def dedicated(data):
    config = data / 'UserData' / 'Config' / 'dedicated_cfg.txt'
    template = config if config.exists() else config.with_name('dedicated_cfg.default.txt')
    tree = ET.parse(template)
    root = tree.getroot()

    def set_value(path, value):
        element = root.find(path)
        if element is None:
            parent, name = path.rsplit('/', 1)
            element = ET.SubElement(root.find(parent), name)
        element.text = value

    for level in root.findall('authorization_levels/level'):
        if level.findtext('name') == 'SuperAdmin':
            level.find('password').text = os.environ['XMLRPC_PASSWORD']

    defaults = {
        'server_options/name': ('TM_SERVER_NAME', 'Trackmania LAN'),
        'server_options/max_players': ('TM_MAX_PLAYERS', '10'),
        'server_options/password': ('TM_PASSWORD', ''),
        'server_options/password_spectator': ('TM_SPECTATOR_PASSWORD', ''),
        'masterserver_account/login': ('TM_MASTER_LOGIN', ''),
        'masterserver_account/password': ('TM_MASTER_PASSWORD', ''),
        'system_config/force_ip_address': ('TM_FORCE_IP', ''),
    }
    for path, (variable, default) in defaults.items():
        set_value(path, os.environ.get(variable, root.findtext(path) or default))
    # Le modèle Nadeo contient 32 slots : notre défaut est 10 au premier lancement.
    if not config.exists() and 'TM_MAX_PLAYERS' not in os.environ:
        set_value('server_options/max_players', '10')
    set_value('system_config/xmlrpc_port', '5000')
    set_value('system_config/xmlrpc_allowremote', 'False')
    tree.write(config, encoding='utf-8', xml_declaration=True)


def pyplanet(data):
    project = data / 'pyplanet'
    marker = project / '.settings_v2'
    if marker.exists():
        return
    settings = {
        'OWNERS': {'default': [login.strip() for login in os.environ.get('PP_OWNERS', 'Zu6CMuX5SkWlrdVjBph28A').split(',') if login.strip()]},
        'SELF_UPGRADE': False,
        'DATABASES': {'default': {
            'ENGINE': 'peewee_async.MySQLDatabase',
            'NAME': 'pyplanet',
            'OPTIONS': {
                'host': '127.0.0.1', 'user': 'pyplanet',
                'password': os.environ['DB_PASSWORD'], 'charset': 'utf8mb4',
            },
        }},
        'DEDICATED': {'default': {
            'HOST': '127.0.0.1', 'PORT': '5000', 'USER': 'SuperAdmin',
            'PASSWORD': os.environ['XMLRPC_PASSWORD'],
        }},
        'MAP_MATCHSETTINGS': {'default': 'tracklist.txt'},
    }
    # repr produit des littéraux Python valides, y compris pour les mots de passe.
    with (project / 'settings' / 'base.py').open('a', encoding='utf-8') as output:
        output.write('\n# Réglages tm-aio (modifiables après le premier lancement).\n')
        for name, value in settings.items():
            output.write('{} = {!r}\n'.format(name, value))
    marker.touch()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=('dedicated', 'pyplanet'))
    args = parser.parse_args()
    data = Path(os.environ.get('DATA_DIR', '/data'))
    {'dedicated': dedicated, 'pyplanet': pyplanet}[args.target](data)
