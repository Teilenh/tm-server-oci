#!/usr/bin/env python3
"""Au premier lancement : télécharge les Weekly Shorts du moment et génère tracklist.txt.

Adapté de setup_server.py (même API trackmania.io, même format de MatchSettings).
Best-effort : en cas d'échec (réseau, API), on sort sans erreur et l'entrypoint
retombe sur le fichier d'exemple du serveur. Usage : bootstrap_maps.py <UserData>
"""
import json
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

API = "https://trackmania.io/api"
TIME_LIMIT = "600"  # secondes par map en Time Attack ; modifiable dans tracklist.txt


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "tm-aio-container/0.1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def main(userdata):
    maps_root = Path(userdata) / "Maps"
    match_path = maps_root / "MatchSettings" / "tracklist.txt"
    if match_path.exists():
        return
    try:
        campaigns = json.loads(download(API + "/campaigns/weeklyshorts/0"))["campaigns"]
        campaign = max((c for c in campaigns if c["timestamp"] <= time.time()),
                       key=lambda c: c["timestamp"])
        playlist = json.loads(download(f"{API}/campaign/weeklyshorts/{campaign['id']}"))["playlist"]
        folder = maps_root / "WeeklyShorts"
        folder.mkdir(parents=True, exist_ok=True)
        files = []
        for index, track in enumerate(playlist, 1):
            content = download(track["fileUrl"])
            if not content.startswith(b"GBX"):
                raise ValueError("téléchargement de map invalide (pas un GBX)")
            name = f"weekly-short-{index:02}.Map.Gbx"
            (folder / name).write_bytes(content)
            files.append("WeeklyShorts/" + name)
            print(f"[bootstrap] map {index} : {track.get('name')}", flush=True)
    except Exception as error:  # noqa: BLE001 - best-effort volontaire
        print(f"[bootstrap] impossible de récupérer les maps ({error}) ; repli sur l'exemple.", flush=True)
        return

    match = ET.Element("playlist")
    game = ET.SubElement(match, "gameinfos")
    ET.SubElement(game, "game_mode").text = "0"
    ET.SubElement(game, "script_name").text = "Trackmania/TM_TimeAttack_Online"
    settings = ET.SubElement(match, "mode_script_settings")
    ET.SubElement(settings, "setting", name="S_TimeLimit", type="integer", value=TIME_LIMIT)
    ET.SubElement(match, "startindex").text = "0"
    for file in files:
        ET.SubElement(ET.SubElement(match, "map"), "file").text = file
    match_path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(match).write(match_path, encoding="utf-8", xml_declaration=True)
    print(f"[bootstrap] tracklist.txt créé avec {len(files)} maps.", flush=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/data/UserData")
