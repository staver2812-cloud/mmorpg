"""Populate Ashen Veil NPCs across outdoor tier bands on Railway Postgres."""
from __future__ import annotations

import pathlib
import sys

import psycopg2
from psycopg2.extras import Json

ZONE = "Пепельный Берег"
SEED = "ashen_veil_world_population"


def tier_for_level(level: int) -> int:
    return (((max(1, min(50, int(level))) - 1) * 22) // 49) + 1


def main() -> None:
    url = pathlib.Path(r"C:\Users\comp1\AppData\Local\Temp\nl_db_url2.txt").read_text().strip()
    conn = psycopg2.connect(url, sslmode="require")
    conn.autocommit = True
    cur = conn.cursor()

    pools: dict[int, list[str]] = {}
    cur.execute(
        "SELECT key, COALESCE((enhancement_rules->'shop'->>'tier')::int, 1) "
        "FROM item_templates WHERE enhancement_rules->'ashen_veil' IS NOT NULL"
    )
    for key, tier in cur.fetchall():
        pools.setdefault(int(tier or 1), []).append(key)

    cur.execute(
        "SELECT id, npc_key, name, level, metadata FROM npc_templates WHERE npc_key LIKE 'av_%' ORDER BY level, id"
    )
    templates = cur.fetchall()
    if not templates:
        print("no av_ templates")
        sys.exit(1)

    # Occupied cells
    cur.execute("SELECT x, y FROM tile_npcs WHERE zone=%s", (ZONE,))
    occupied = {(r[0], r[1]) for r in cur.fetchall()}

    placed = updated = 0
    for idx, (tid, npc_key, name, level, meta) in enumerate(templates):
        meta = dict(meta or {})
        tier = tier_for_level(level)
        role = str(meta.get("ashen_role") or "normal")
        respawn = 1800 if role == "boss" else (600 if role == "elite" else 180)
        candidates = list(
            dict.fromkeys(
                (pools.get(tier) or [])
                + (pools.get(max(tier - 1, 1)) or [])
                + (pools.get(min(tier + 1, 23)) or [])
            )
        )
        sample = candidates[:4]
        chances = [35, 28, 22, 15] if role == "boss" else ([22, 16, 12, 8] if role == "elite" else [12, 9, 6, 4])
        loot = [
            {"kind": "item", "item_key": k, "quantity": 1, "chance": chances[i] if i < len(chances) else 5}
            for i, k in enumerate(sample)
        ]
        silver = int(meta.get("silver") or 0)
        nv = silver if silver > 0 else max(tier * 4, 5)
        loot.append({"kind": "currency", "currency": "NV", "amount": nv, "chance": 100 if role == "boss" else 75})

        meta.update(
            {
                "loot_table": loot,
                "respawn_seconds": respawn,
                "respawn_variance_seconds": max(30, min(respawn // 5, 600)),
                "drop_chance_multiplier": float(meta.get("drop_chance_multiplier") or 1.0),
                "world_tier": tier,
                "seed_source": SEED,
            }
        )
        cur.execute("UPDATE npc_templates SET metadata=%s, updated_at=NOW() WHERE id=%s", (Json(meta), tid))

        base_x = ((tier - 1) * 900 // 23) + 12
        x = base_x + (idx % 5) * 3
        y = 30 + ((idx // 5) % 40) * 5
        # Find free cell
        for _ in range(40):
            if (x, y) not in occupied:
                break
            x += 2
            if x > 950:
                x = base_x
                y += 3
        occupied.add((x, y))

        hp = int(meta.get("health") or meta.get("max_hp") or 50)
        placement = {
            "active": True,
            "seed_source": SEED,
            "world_tier": tier,
            "respawn_seconds": respawn,
            "respawn_variance_seconds": meta["respawn_variance_seconds"],
            "drop_chance_multiplier": meta["drop_chance_multiplier"],
            "encounter_count": 1,
        }
        cur.execute("SELECT id FROM tile_npcs WHERE zone=%s AND x=%s AND y=%s", (ZONE, x, y))
        row = cur.fetchone()
        if row:
            cur.execute(
                """
                UPDATE tile_npcs SET npc_template_id=%s, npc_key=%s, npc_role='hostile', level=%s,
                  max_hp=%s, current_hp=%s, defeated_at=NULL, respawns_at=NULL,
                  metadata=%s, updated_at=NOW()
                WHERE id=%s
                """,
                (tid, npc_key, level, hp, hp, Json(placement), row[0]),
            )
            updated += 1
        else:
            cur.execute(
                """
                INSERT INTO tile_npcs
                  (zone, x, y, npc_template_id, npc_key, npc_role, level, max_hp, current_hp,
                   metadata, created_at, updated_at)
                VALUES (%s,%s,%s,%s,%s,'hostile',%s,%s,%s,%s,NOW(),NOW())
                """,
                (ZONE, x, y, tid, npc_key, level, hp, hp, Json(placement)),
            )
            placed += 1

    cur.execute(
        "SELECT count(*) FROM tile_npcs WHERE metadata->>'seed_source'=%s",
        (SEED,),
    )
    print(f"population placed={placed} updated={updated} ashen_tiles={cur.fetchone()[0]}")
    cur.execute(
        "SELECT world_tier, count(*) FROM ("
        " SELECT (metadata->>'world_tier')::int AS world_tier FROM tile_npcs "
        " WHERE metadata->>'seed_source'=%s"
        ") t GROUP BY 1 ORDER BY 1",
        (SEED,),
    )
    print("tiers", cur.fetchall())
    conn.close()


if __name__ == "__main__":
    main()
