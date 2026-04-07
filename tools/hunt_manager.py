#!/usr/bin/env python3
"""
Hunt Manager — local HTTP server for hunt curation UI.

Serves the management UI with wiki data + server monster list auto-embedded.
Provides API endpoints for saving state and exporting Lua directly to project.

Usage:
    python3 tools/hunt_manager.py [--port 8099]
"""

import json
import os
import re
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

# Project root: two levels up from tools/
PROJECT_ROOT = Path(__file__).resolve().parent.parent
WIKI_DATA_PATH = PROJECT_ROOT / "data" / "hunt_wiki_raw.json"
STATE_PATH = PROJECT_ROOT / "data" / "hunt_wiki_state.json"
LUA_EXPORT_PATH = PROJECT_ROOT / "data" / "libs" / "functions" / "wiki_hunts_import.lua"
HTML_PATH = Path(__file__).resolve().parent / "hunt_manager.html"
MONSTER_DIRS = [
    PROJECT_ROOT / "data-crystal" / "monster",
    PROJECT_ROOT / "data-global" / "monster",
]

PORT = 8099


def scan_server_monsters() -> list[str]:
    """Extract monster names from Game.createMonsterType('Name') in Lua files."""
    names = set()
    pattern = re.compile(r'Game\.createMonsterType\("([^"]+)"\)')
    for monster_dir in MONSTER_DIRS:
        if not monster_dir.exists():
            continue
        for lua_file in monster_dir.rglob("*.lua"):
            try:
                content = lua_file.read_text(encoding="utf-8", errors="replace")
                for match in pattern.finditer(content):
                    names.add(match.group(1))
            except Exception:
                pass
    return sorted(names)


def load_wiki_data() -> dict | None:
    if WIKI_DATA_PATH.exists():
        with open(WIKI_DATA_PATH, encoding="utf-8") as f:
            return json.load(f)
    return None


def load_state() -> dict:
    if STATE_PATH.exists():
        with open(STATE_PATH, encoding="utf-8") as f:
            data = json.load(f)
            return data.get("huntState", {})
    return {}


def save_state(hunt_state: dict):
    export_data = {
        "exportedAt": __import__("time").strftime("%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime()),
        "huntState": hunt_state,
    }
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(export_data, f, ensure_ascii=False, indent=2)


def normalize_creature_name(name: str) -> str:
    """Strip wiki disambiguation suffixes like ' (Criatura)', ' (Anti-Botter)', etc."""
    return re.sub(r'\s*\([^)]+\)$', '', name)


def export_lua(hunt_state: dict, wiki_data: dict) -> int:
    """Generate Lua file for hunts marked as 'import'. Returns count."""
    hunts = wiki_data.get("hunts", [])
    import_hunts = [h for h in hunts if hunt_state.get(h["name"], {}).get("status") == "import"]

    if not import_hunts:
        return 0

    # Build case-insensitive lookup: wiki name -> server's exact name
    server_monsters = scan_server_monsters()
    server_by_lower = {n.lower(): n for n in server_monsters}

    def resolve_creature_name(wiki_name: str) -> str:
        """Return server's exact name if found, otherwise normalized wiki name."""
        normalized = normalize_creature_name(wiki_name)
        return server_by_lower.get(normalized.lower(), normalized)

    lines = [
        "-- Auto-generated from Hunt Manager",
        f"-- {__import__('time').strftime('%Y-%m-%dT%H:%M:%SZ', __import__('time').gmtime())}",
        f"-- {len(import_hunts)} hunts marked for import",
        "",
        "WIKI_HUNTS = {",
    ]

    for h in import_hunts:
        coords = h.get("coords") or {"x": 0, "y": 0, "z": 0}
        creatures = ", ".join(f'"{resolve_creature_name(c)}"' for c in (h.get("creatures") or []))
        rares = ", ".join(f'"{r}"' for r in (h.get("rareItems") or []))
        lines.append(f"  {{")
        lines.append(f'    name = "{h["name"]}",')
        lines.append(f'    city = "{h.get("city", "")}",')
        lines.append(f'    level = {h.get("level") or 0},')
        lines.append(f'    difficulty = {h.get("difficulty") or 0},')
        lines.append(f'    expRating = {h.get("expRating") or 0},')
        lines.append(f'    lootRating = {h.get("lootRating") or 0},')
        lines.append(f'    premium = {str(h.get("premium", False)).lower()},')
        lines.append(f'    seedPos = Position({coords["x"]}, {coords["y"]}, {coords["z"]}),')
        lines.append(f'    creatures = {{ {creatures} }},')
        lines.append(f'    rareItems = {{ {rares} }},')
        lines.append(f'    wikiUrl = "{h.get("wikiUrl", "")}",')
        lines.append(f"  }},")

    lines.append("}")
    lines.append("")

    LUA_EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(LUA_EXPORT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    return len(import_hunts)


class HuntManagerHandler(SimpleHTTPRequestHandler):
    wiki_data = None
    server_monsters = None
    hunt_state = None

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            html = HTML_PATH.read_text(encoding="utf-8")
            self.wfile.write(html.encode("utf-8"))
        elif self.path == "/api/data":
            self.send_json({
                "wikiData": HuntManagerHandler.wiki_data,
                "serverMonsters": HuntManagerHandler.server_monsters,
                "savedState": HuntManagerHandler.hunt_state,
            })
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(content_len)) if content_len > 0 else {}

        if self.path == "/api/save-state":
            hunt_state = body.get("huntState", {})
            HuntManagerHandler.hunt_state = hunt_state
            save_state(hunt_state)
            self.send_json({"ok": True, "path": str(STATE_PATH)})

        elif self.path == "/api/export-lua":
            hunt_state = body.get("huntState", {})
            count = export_lua(hunt_state, HuntManagerHandler.wiki_data or {})
            self.send_json({"ok": True, "count": count, "path": str(LUA_EXPORT_PATH)})

        else:
            self.send_response(404)
            self.end_headers()

    def send_json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def log_message(self, format, *args):
        # Quieter logging
        pass


def main():
    port = PORT
    if "--port" in sys.argv:
        idx = sys.argv.index("--port")
        port = int(sys.argv[idx + 1])

    print(f"[Hunt Manager] Loading data...")

    # Load wiki data
    wiki_data = load_wiki_data()
    if wiki_data:
        print(f"  Wiki data: {wiki_data['totalHunts']} hunts from {WIKI_DATA_PATH}")
    else:
        print(f"  WARNING: No wiki data found at {WIKI_DATA_PATH}")
        print(f"  Run: python3 tools/scrape_wiki_hunts.py --with-creatures")
        wiki_data = {"hunts": [], "totalHunts": 0}

    # Scan server monsters
    monsters = scan_server_monsters()
    print(f"  Server monsters: {len(monsters)} found")

    # Load saved state
    hunt_state = load_state()
    print(f"  Saved state: {len(hunt_state)} entries from {STATE_PATH}")

    # Set class-level data
    HuntManagerHandler.wiki_data = wiki_data
    HuntManagerHandler.server_monsters = monsters
    HuntManagerHandler.hunt_state = hunt_state

    print(f"\n  Open in browser: http://localhost:{port}")
    print(f"  Press Ctrl+C to stop\n")

    server = HTTPServer(("0.0.0.0", port), HuntManagerHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[Hunt Manager] Stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
