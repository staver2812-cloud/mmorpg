#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""End-to-end smoke against the live Ashen Veil / Neverlands Railway sandbox.

Usage:
  python scripts/ashen_smoke.py
  set SMOKE_BASE=https://web-production-bc5d0.up.railway.app
"""

from __future__ import annotations

import os
import re
import sys
import time
import uuid
from dataclasses import dataclass, field
from typing import List, Optional, Tuple
from urllib.parse import urljoin

import requests

BASE = os.environ.get("SMOKE_BASE", "https://web-production-bc5d0.up.railway.app").rstrip("/")
TIMEOUT = float(os.environ.get("SMOKE_TIMEOUT", "30"))


@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class Report:
    checks: List[Check] = field(default_factory=list)

    def add(self, name: str, ok: bool, detail: str = "") -> None:
        self.checks.append(Check(name, ok, detail))
        mark = "OK" if ok else "FAIL"
        print(f"[{mark}] {name}" + (f" — {detail}" if detail else ""))

    @property
    def failed(self) -> List[Check]:
        return [c for c in self.checks if not c.ok]


def csrf_from(html: str) -> Optional[str]:
    m = re.search(r'name="csrf-token"\s+content="([^"]+)"', html)
    if m:
        return m.group(1)
    m = re.search(r'name="authenticity_token"[^>]*value="([^"]+)"', html)
    if m:
        return m.group(1)
    m = re.search(r'value="([^"]+)"[^>]*name="authenticity_token"', html)
    return m.group(1) if m else None


def parse_hotspot_forms(html: str) -> dict:
    """Map data-hotspot-key -> (hotspot_id, action_key, authenticity_token)."""
    out = {}
    for m in re.finditer(r"<form\b[^>]*interact_hotspot[^>]*>(.*?)</form>", html, flags=re.S | re.I):
        block = m.group(0)
        hid = re.search(r'value="(\d+)"[^>]*name="hotspot_id"|name="hotspot_id"[^>]*value="(\d+)"', block)
        akey = re.search(r'value="([^"]+)"[^>]*name="action_key"|name="action_key"[^>]*value="([^"]+)"', block)
        key = re.search(r'data-hotspot-key="([^"]+)"', block)
        tok = re.search(
            r'value="([^"]+)"[^>]*name="authenticity_token"|name="authenticity_token"[^>]*value="([^"]+)"',
            block,
        )
        if hid and akey and key:
            hotspot_id = hid.group(1) or hid.group(2)
            action_key = akey.group(1) or akey.group(2)
            authenticity = (tok.group(1) or tok.group(2)) if tok else None
            out[key.group(1)] = (hotspot_id, action_key, authenticity)
    return out


def click_hotspot(session: requests.Session, key: str) -> Tuple[bool, str]:
    r = session.get(f"{BASE}/world", timeout=TIMEOUT)
    forms = parse_hotspot_forms(r.text)
    if key not in forms:
        return False, f"hotspot {key} missing; have={sorted(forms)[:12]}"
    hotspot_id, action_key, form_token = forms[key]
    token = form_token or csrf_from(r.text)
    r = session.post(
        f"{BASE}/world/interact_hotspot",
        data={
            "authenticity_token": token,
            "hotspot_id": hotspot_id,
            "action_key": action_key,
        },
        timeout=TIMEOUT,
        allow_redirects=True,
    )
    return r.status_code == 200, f"status={r.status_code} url={r.url} keys={sorted(parse_hotspot_forms(r.text))[:8]}"


def main() -> int:
    report = Report()
    s = requests.Session()
    s.headers.update({"User-Agent": "ashen-smoke/1.0", "Accept-Language": "ru"})

    try:
        r = s.get(f"{BASE}/up", timeout=TIMEOUT)
        report.add("GET /up", r.status_code == 200, str(r.status_code))
    except Exception as exc:
        report.add("GET /up", False, str(exc))
        print("Abort: base unreachable")
        return 1

    r = s.get(f"{BASE}/users/sign_up", timeout=TIMEOUT)
    html = r.text
    report.add("GET /users/sign_up", r.status_code == 200, str(r.status_code))
    report.add("signup has nickname field", 'name="user[profile_name]"' in html or "Игровой ник" in html)
    report.add("signup RU chrome", "Создать" in html or "Пепельная" in html)
    token = csrf_from(html)
    report.add("signup CSRF", bool(token), "missing" if not token else "ok")

    nick = f"Smoke{uuid.uuid4().hex[:8]}"
    email = f"smoke_{uuid.uuid4().hex[:10]}@example.com"
    password = "SmokePass123!"

    if token:
        r = s.post(
            f"{BASE}/users",
            data={
                "authenticity_token": token,
                "user[profile_name]": nick,
                "user[email]": email,
                "user[password]": password,
                "user[password_confirmation]": password,
                "commit": "Создать аккаунт",
            },
            timeout=TIMEOUT,
            allow_redirects=True,
        )
        body = r.text
        ok_reg = r.status_code in (200, 302) and (
            nick in body or "nl-map" in body or "city-view" in body or "/world" in r.url
        )
        report.add("POST register + land in game", ok_reg, f"status={r.status_code} url={r.url}")
        report.add("character nick visible", nick in body, nick)
    else:
        report.add("POST register + land in game", False, "no csrf")

    for path, needles in [
        ("/world", ["city-view", "nl-city", "Пепельный", "Город", "Площадь"]),
        ("/shop", ["Лавка", "nl-shop", "NV", "Купить"]),
        ("/inventory", ["nl-inventory", "Вес инвентаря", "Надеть", "Свойства"]),
        (f"/player/{nick}", ["nl-character-sheet", "Сейф", "nl-sheet-vault", "Ячейка", "nl-sheet-locker"]),
        ("/arena", ["nl-arena", "Арена", "Дуэли"]),
        ("/city/buildings/tavern", ["data-building-key=\"tavern\"", "Отдохнуть за столом", "Слухи угля"]),
        ("/city/buildings/guard_tower", ["data-building-key=\"guard_tower\"", "interact_hotspot", "Карта кварталов"]),
        ("/city/buildings/workshop", ["data-building-key=\"workshop\"", "Смолокур", "Скрафтить"]),
        ("/city/buildings/hospital", ["data-building-key=\"hospital\"", "Лазарет", "Лекарь", "в сумке:"]),
    ]:
        r = s.get(urljoin(BASE + "/", path.lstrip("/")), timeout=TIMEOUT)
        hit = any(n in r.text for n in needles)
        report.add(f"GET {path}", r.status_code == 200 and hit, f"{r.status_code} needles={hit}")
        time.sleep(0.1)

    r = s.get(f"{BASE}/shop?mode=sell", timeout=TIMEOUT)
    report.add(
        "shop sell junk hint",
        r.status_code == 200
        and 'nl-shop' in r.text
        and (("Скупщик" in r.text) or ("Ash Buyer" in r.text) or ("junk_dealer" in r.text)),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add(
        "trauma scroll chip on square",
        r.status_code == 200 and (("Напасть:" in r.text) or ("nl-trauma-chip" in r.text) or ("Attack:" in r.text)),
        f"url={r.url}",
    )

    ok, detail = click_hotspot(s, "go_forpost1")
    report.add("travel go_forpost1", ok, detail)
    r = s.get(f"{BASE}/city/buildings/market", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/market junk",
        r.status_code == 200
        and 'data-building-key="market"' in r.text
        and ("Скупщик" in r.text or "junk" in r.text.lower())
        and ("Сдать" in r.text or "Sell" in r.text or "пусто" in r.text.lower() or "empty" in r.text.lower() or "NV" in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/city_hall", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/city_hall",
        r.status_code == 200 and 'data-building-key="city_hall"' in r.text,
        f"url={r.url}",
    )
    if r.status_code == 200:
        report.add("city_hall quest board", "Задания" in r.text or "/quests" in r.text)
        report.add(
            "city_hall treasury",
            ("Казна" in r.text) or ("treasury" in r.text.lower()) or ("сейф" in r.text.lower()),
        )
        report.add(
            "city_hall residential links",
            ("записк" in r.text.lower() or "/city/buildings/post" in r.text)
            and ("Зал Клана" in r.text or "/city/buildings/clan_hall" in r.text),
        )
    r = s.get(f"{BASE}/city/buildings/post", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/post",
        r.status_code == 200 and 'data-building-key="post"' in r.text and ("записк" in r.text.lower() or "note" in r.text.lower()),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/clan_hall", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/clan_hall",
        r.status_code == 200 and 'data-building-key="clan_hall"' in r.text and ("Напасть" in r.text or "Attack" in r.text or "свитк" in r.text.lower()),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/airship_station", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/airship_station wallet",
        r.status_code == 200
        and 'data-building-key="airship_station"' in r.text
        and ("В кармане" in r.text or "Wallet" in r.text),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/quests", timeout=TIMEOUT)
    quest_needles = [
        "Приманка Завесы",
        "Хвост Завесы",
        "Первый бинт Смолокура",
        "Первая сумка Лекаря",
        "Полевой набор Смолокура",
        "Пепельный дозор",
        "Разведка берега",
        "След соли",
        "Крошки колокольного двора",
        "Колокольный выводок",
        "Зачистка патруля",
        "Призраки соляного пирса",
        "Награда за ножевика",
        "Заглушить пыль",
        "nl-quests",
        "nl-quests__summary",
        "Закрыто",
    ]
    quest_hits = [n for n in quest_needles if n in r.text]
    report.add(
        "GET /quests",
        r.status_code == 200 and len(quest_hits) >= 8,
        f"{r.status_code} hits={quest_hits}",
    )
    if r.status_code == 200:
        token = csrf_from(r.text) or token
        report.add(
            "starter lure active on journal",
            ("Приманка Завесы" in r.text) and ("В работе" in r.text),
        )
        report.add(
            "chain shows locked contracts",
            ("Закрыто" in r.text) and ("Хвост Завесы" in r.text),
        )
        # Chain gate: veil_tail requires lure completion — expect safe reject.
        r_acc = s.post(
            f"{BASE}/quests/veil_tail_delivery/accept",
            data={"authenticity_token": token},
            timeout=TIMEOUT,
            allow_redirects=True,
        )
        locked_ok = (
            r_acc.status_code in (200, 302)
            and (
                "предыдущие" in r_acc.text.lower()
                or "locked" in r_acc.text.lower()
                or "цепи" in r_acc.text.lower()
                or "Закрыто" in r_acc.text
            )
        )
        report.add(
            "POST accept veil_tail_delivery locked",
            locked_ok,
            f"{r_acc.status_code}",
        )
        report.add(
            "quests show rewards",
            ("Опыт:" in r.text) or ("NV:" in r.text) or ("Предмет:" in r.text) or ("XP:" in r.text),
        )
        report.add(
            "quests show where hints",
            ("Где:" in r.text) or ("Where:" in r.text),
        )

    ok_main, d1 = click_hotspot(s, "go_main")
    report.add("travel go_main", ok_main, d1)
    ok_f1, d_f1 = click_hotspot(s, "go_forpost1")
    report.add("travel go_forpost1 for library", ok_f1, d_f1)
    ok_f2, d_f2 = click_hotspot(s, "go_forpost2")
    report.add("travel go_forpost2", ok_f2, d_f2)

    r = s.get(f"{BASE}/city/buildings/library", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/library handbook",
        r.status_code == 200 and "Справочник Пепельной Завесы" in r.text,
        f"url={r.url}",
    )
    if r.status_code == 200:
        report.add(
            "library covers Assault and quest chain",
            ("PvP на клетке" in r.text) and ("Цепь:" in r.text or "Приманка →" in r.text),
        )
        report.add(
            "library covers Obelisk Law fatigue",
            ("Обелиск" in r.text) and ("Склонность" in r.text) and ("Усталость" in r.text),
        )

    ok_main2, _ = click_hotspot(s, "go_forpost1")
    report.add("return forpost1 after library", ok_main2)
    ok_main3, d1b = click_hotspot(s, "go_main")
    report.add("return main before forpost3", ok_main3, d1b)
    ok, detail = click_hotspot(s, "go_forpost3")
    report.add("travel go_forpost3", ok, detail)

    r = s.get(f"{BASE}/city/buildings/temple", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/temple",
        r.status_code == 200 and 'data-building-key="temple"' in r.text and ("обряд" in r.text.lower() or "rite" in r.text.lower()),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/city/buildings/bank", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/bank",
        r.status_code == 200
        and 'data-building-key="bank"' in r.text
        and ("Сейф" in r.text or "vault" in r.text.lower())
        and ("Ячейка" in r.text or "locker" in r.text.lower()),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/souvenir_shop", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/souvenir_shop",
        r.status_code == 200 and 'data-building-key="souvenir_shop"' in r.text and ("Приманка" in r.text or "bait" in r.text.lower()),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/obelisk", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/obelisk",
        r.status_code == 200
        and 'data-building-key="obelisk"' in r.text
        and ("Привязать" in r.text or "Bind" in r.text),
        f"url={r.url}",
    )

    ok_main_tav, detail_main_tav = click_hotspot(s, "go_main")
    report.add("return main before tavern fatigue", ok_main_tav, detail_main_tav)
    r = s.get(f"{BASE}/city/buildings/tavern", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/tavern fatigue copy",
        r.status_code == 200
        and 'data-building-key="tavern"' in r.text
        and ("устал" in r.text.lower() or "fatigue" in r.text.lower()),
        f"url={r.url}",
    )
    ok_f1_law, d_f1_law = click_hotspot(s, "go_forpost1")
    report.add("travel go_forpost1 for law", ok_f1_law, d_f1_law)
    ok_f4, d_f4 = click_hotspot(s, "go_forpost4")
    report.add("travel go_forpost4", ok_f4, d_f4)
    r = s.get(f"{BASE}/city/buildings/law_abode", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/law_abode",
        r.status_code == 200
        and 'data-building-key="law_abode"' in r.text
        and ("склонност" in r.text.lower() or "alignment" in r.text.lower()),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add(
        "alignment chip on Law Quarter",
        ("Склонность?" in r.text) or ("nl-alignment-chip" in r.text) or ("Alignment?" in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/prison", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/prison",
        r.status_code == 200
        and 'data-building-key="prison"' in r.text
        and ("Обитель Закона" in r.text or "Law Abode" in r.text or "law_abode" in r.text),
        f"url={r.url}",
    )

    for path in [
        "/ashen/items/set-blood/helm.png",
        "/ashen/items/set-demiurge/weapon-sword.png",
        "/ashen/items/set-judge/armor-plate.png",
    ]:
        r = s.get(urljoin(BASE + "/", path.lstrip("/")), timeout=TIMEOUT)
        ok = r.status_code == 200 and len(r.content) > 100
        report.add(f"GET {path}", ok, f"{r.status_code} bytes={len(r.content)}")

    r = s.get(f"{BASE}/inventory", timeout=TIMEOUT)
    banned = ["Wear", "Properties", "Requirements", "Inventory mass", "Equipment Sets", "Transfer"]
    found_en = [w for w in banned if w in r.text]
    report.add("inventory no English chrome", not found_en, f"found={found_en}")
    report.add(
        "inventory junk hint or link",
        ("Скупщику:" in r.text) or ("Junk buyer:" in r.text),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/shop", timeout=TIMEOUT)
    banned_shop = ["You carry", "Shop funds", "Refresh to buy", "There are no items"]
    found_shop = [w for w in banned_shop if w in r.text]
    report.add("shop no English chrome", not found_shop, f"found={found_shop}")

    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add("locale switcher", ("RU" in r.text and "EN" in r.text) or "/locales" in r.text)

    ok_back_f1, d_back_f1 = click_hotspot(s, "go_forpost1")
    report.add("return forpost1 after law", ok_back_f1, d_back_f1)
    ok, detail_main = click_hotspot(s, "go_main")
    report.add("return go_main", ok, detail_main)
    r = s.get(f"{BASE}/city/buildings/temple", timeout=TIMEOUT, allow_redirects=True)
    gated = "/world" in r.url or 'data-building-key="temple"' not in r.text
    report.add("temple gated from main square", gated, f"url={r.url}")

    ok_gate, gate_detail = click_hotspot(s, "west_gate")
    report.add("travel west_gate", ok_gate, gate_detail)
    if ok_gate:
        r = s.get(f"{BASE}/world", timeout=TIMEOUT)
        outdoorish = ("Пепельный Берег" in r.text) or ("nl-world-map" in r.text) or ("available-actions" in r.text)
        report.add("outdoor after west_gate", r.status_code == 200 and outdoorish, f"{r.status_code}")
        report.add(
            "outdoor bait chip",
            ("Приманка:" in r.text) or ("nl-bait-chip" in r.text),
        )

    failed = report.failed
    print("\n=== SUMMARY ===")
    print(f"passed={len(report.checks) - len(failed)} failed={len(failed)} total={len(report.checks)}")
    for c in failed:
        print(f"  - {c.name}: {c.detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
