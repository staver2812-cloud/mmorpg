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


def enter_building(session: requests.Session) -> Tuple[bool, str]:
    r = session.get(f"{BASE}/world", timeout=TIMEOUT)
    m = re.search(
        r'<form[^>]*action="/world/enter_building"[^>]*>(.*?)</form>',
        r.text,
        flags=re.S | re.I,
    )
    if not m:
        return False, "no enter_building form"
    block = m.group(0)
    bid = re.search(r'name="building_id"[^>]*value="(\d+)"|value="(\d+)"[^>]*name="building_id"', block)
    akey = re.search(r'name="action_key"[^>]*value="([^"]+)"|value="([^"]+)"[^>]*name="action_key"', block)
    tok = re.search(
        r'name="authenticity_token"[^>]*value="([^"]+)"|value="([^"]+)"[^>]*name="authenticity_token"',
        block,
    )
    if not (bid and akey and tok):
        return False, "enter_building fields missing"
    building_id = bid.group(1) or bid.group(2)
    action_key = akey.group(1) or akey.group(2)
    authenticity = tok.group(1) or tok.group(2)
    r = session.post(
        f"{BASE}/world/enter_building",
        data={
            "authenticity_token": authenticity,
            "building_id": building_id,
            "action_key": action_key,
        },
        timeout=TIMEOUT,
        allow_redirects=True,
    )
    keys = sorted(parse_hotspot_forms(r.text))
    return r.status_code == 200 and bool(keys), f"status={r.status_code} url={r.url} keys={keys[:8]}"


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
        ("/world", ["city-view", "nl-city", "Пепельный", "Город", "Площадь", "data-presence-count=", "data-online-total="]),
        ("/shop", ["Лавка", "nl-shop", "NV", "Купить", "data-shop-wallet=", "data-shop-any-affordable="]),
        ("/inventory", ["nl-inventory", "Вес инвентаря", "Надеть", "Свойства"]),
        (f"/player/{nick}", ["nl-character-sheet", "Сейф", "nl-sheet-vault", "data-sheet-vault=", "Ячейка", "nl-sheet-locker", "data-sheet-locker=", "nl-sheet-vm", "data-sheet-vm=", "data-sheet-nv="]),
        # Arena lobby markers are asserted after city arena entry; early GET redirects to /world.
        ("/city/buildings/tavern", ["data-building-key=\"tavern\"", "Отдохнуть за столом", "data-tavern-rumors=", "data-tavern-rumors-next=", "data-tavern-vitals=", "data-tavern-hp=", "data-tavern-mp=", "data-tavern-ready="]),
        ("/city/buildings/guard_tower", ["data-building-key=\"guard_tower\"", "interact_hotspot", "data-guard-square=", "data-guard-square-next=", "data-guard-here=", "data-guard-routes=", "data-landmark-inside=\"1\""]),
        ("/city/buildings/workshop", ["data-building-key=\"workshop\"", "Смолокур", "Скрафтить", "data-workshop-repair=\"deferred\"", "data-workshop-mass=", "data-workshop-any-ready=", "data-workshop-recipe=", "data-workshop-ready=", "data-workshop-landmark=", "data-workshop-landmark-next=", "data-landmark-inside=\"1\""]),
        ("/city/buildings/hospital", ["data-building-key=\"hospital\"", "Лазарет", "Лекарь", "в сумке:", "data-hospital-assault=", "data-hospital-heal=", "data-hospital-vitals=", "data-hospital-vm=", "data-hospital-premium-affordable=", "data-hospital-premium-any-affordable=", "data-hospital-topup-ready=", "data-hospital-injuries=", "data-hospital-mass=", "data-hospital-combat=", "data-hospital-rest-ready=", "data-hospital-craft-any-ready=", "data-hospital-recipe=", "data-hospital-craft-ready="]),
    ]:
        r = s.get(urljoin(BASE + "/", path.lstrip("/")), timeout=TIMEOUT)
        data_needles = [n for n in needles if "data-" in n]
        text_needles = [n for n in needles if "data-" not in n]
        data_ok = all(n in r.text for n in data_needles)
        text_ok = (not text_needles) or any(n in r.text for n in text_needles)
        hit = data_ok and text_ok
        missing = [n for n in data_needles if n not in r.text]
        report.add(
            f"GET {path}",
            r.status_code == 200 and hit,
            f"{r.status_code} data_ok={data_ok} text_ok={text_ok} missing={missing[:4]}",
        )
        time.sleep(0.1)

    r = s.get(f"{BASE}/player/{nick}", timeout=TIMEOUT)
    report.add(
        "player allocation idle or form",
        r.status_code == 200
        and (
            'data-profile-allocation="idle"' in r.text
            or 'id="stat-allocation"' in r.text
            or "nl-allocation-frame" in r.text
        ),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/city/buildings/hospital", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "hospital landmark inside chrome",
        r.status_code == 200 and 'data-landmark-inside="1"' in r.text,
        f"url={r.url}",
    )
    report.add(
        "hospital traumatologist desk",
        r.status_code == 200 and 'data-hospital-traumatologist="1"' in r.text,
        f"url={r.url}",
    )
    if 'data-hospital-traumatologist-status="need-perk"' in r.text:
        report.add(
            "hospital traumatologist need-perk recovery",
            'data-hospital-traumatologist-next="1"' in r.text
            and 'data-hospital-recovery="world"' in r.text,
            f"url={r.url}",
        )
    r = s.get(f"{BASE}/city/buildings/tavern", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "tavern landmark inside chrome",
        r.status_code == 200
        and 'data-building-key="tavern"' in r.text
        and 'data-landmark-inside="1"' in r.text
        and 'data-tavern-rumors-next="1"' in r.text,
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/shop?mode=sell", timeout=TIMEOUT)
    report.add(
        "shop sell junk hint",
        r.status_code == 200
        and 'nl-shop' in r.text
        and (("Скупщик" in r.text) or ("Ash Buyer" in r.text) or ("junk_dealer" in r.text))
        and ("data-shop-any-sellable=" in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/shop?mode=licenses", timeout=TIMEOUT)
    report.add(
        "shop licenses localized",
        r.status_code == 200
        and 'nl-shop' in r.text
        and ("data-shop-license=" in r.text)
        and ("data-shop-license-affordable=" in r.text)
        and ("Valid for" not in r.text)
        and (("Срок:" in r.text) or ("дн." in r.text)),
        f"url={r.url}",
    )
    report.add(
        "shop doctor onboarding",
        r.status_code == 200 and 'data-shop-doctor-onboarding="1"' in r.text,
        f"url={r.url}",
    )
    if 'data-shop-licenses-empty="1"' in r.text:
        report.add(
            "shop licenses empty Buy recovery",
            'data-shop-licenses-recovery="buy"' in r.text,
            f"url={r.url}",
        )

    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add(
        "trauma scroll chip on square",
        r.status_code == 200
        and (("Напасть:" in r.text) or ("nl-trauma-chip" in r.text) or ("Attack:" in r.text))
        and ("data-trauma-scrolls=" in r.text),
        f"url={r.url}",
    )
    report.add(
        "heal scroll chip on square",
        r.status_code == 200
        and (("Лечение:" in r.text) or ("nl-heal-chip" in r.text) or ("Heal:" in r.text))
        and ("data-heal-scrolls=" in r.text),
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
        and ("Сдать" in r.text or "Sell" in r.text or "пусто" in r.text.lower() or "empty" in r.text.lower() or "NV" in r.text)
        and ("data-junk-total=" in r.text)
        and ("data-junk-wallet=" in r.text)
        and ("data-market-wallet=" in r.text)
        and ("data-junk-can-sell=" in r.text)
        and ("data-market-stalls=" in r.text)
        and ("data-market-any-stall-affordable=" in r.text)
        and ('data-market-stalls-deferred="1"' in r.text)
        and ('data-market-notice="1"' in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    if 'data-junk-total="0"' in r.text:
        report.add(
            "junk empty Inventory recovery",
            'data-junk-recovery="inventory"' in r.text,
            f"url={r.url}",
        )
    r = s.get(f"{BASE}/city/buildings/numismatics", timeout=TIMEOUT, allow_redirects=True)
    numismatics_open = (
        r.status_code == 200
        and 'data-building-key="numismatics"' in r.text
        and ("data-numismatics=" in r.text)
        and ('data-numismatics-listings="0"' in r.text)
        and ('data-numismatics-deferred="1"' in r.text)
        and ("Нет предложений" in r.text or "No MVP listings" in r.text)
    )
    numismatics_gated = "/world" in r.url or 'data-building-key="numismatics"' not in r.text
    report.add(
        "GET /city/buildings/numismatics empty book or gated",
        numismatics_open or numismatics_gated,
        f"url={r.url} open={numismatics_open}",
    )
    if numismatics_open:
        report.add(
            "numismatics deferred recovery",
            'data-numismatics-recovery="shop"' in r.text,
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
            (("Казна" in r.text) or ("treasury" in r.text.lower()) or ("сейф" in r.text.lower()))
            and ("data-city-hall-wallet=" in r.text)
            and ("data-city-hall-vault=" in r.text)
            and ("data-city-hall-vm=" in r.text),
        )
        report.add(
            "city_hall quest ready count",
            ("data-city-hall-quest-ready=" in r.text)
            and ("data-city-hall-quest-active=" in r.text)
            and ("data-city-hall-quest-available=" in r.text)
            and ("data-city-hall-quest-locked=" in r.text)
            and ("data-city-hall-quest-completed=" in r.text)
            and ("Готово к сдаче" in r.text or "Ready to turn in" in r.text),
        )
        report.add(
            "city_hall residential links",
            ("записк" in r.text.lower() or "/city/buildings/post" in r.text)
            and ("Зал Клана" in r.text or "/city/buildings/clan_hall" in r.text),
        )
        report.add(
            "city_hall landmark inside chrome",
            'data-landmark-inside="1"' in r.text,
        )
    r = s.get(f"{BASE}/city/buildings/post", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/post",
        r.status_code == 200
        and 'data-building-key="post"' in r.text
        and ("записк" in r.text.lower() or "note" in r.text.lower())
        and "data-post-remaining=" in r.text
        and "data-post-empty=" in r.text
        and "data-post-max=" in r.text
        and "data-post-can-clear=" in r.text
        and 'data-landmark-inside="1"' in r.text,
        f"url={r.url}",
    )
    if r.status_code == 200 and 'data-post-empty="1"' in r.text:
        report.add(
            "post empty recovery CTA",
            ("data-post-recovery=" in r.text) or ("/city/buildings/city_hall" in r.text),
            f"url={r.url}",
        )
    r = s.get(f"{BASE}/city/buildings/clan_hall", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/clan_hall",
        r.status_code == 200
        and 'data-building-key="clan_hall"' in r.text
        and ("Напасть" in r.text or "Attack" in r.text or "свитк" in r.text.lower())
        and ('data-clan-hall-presence="1"' in r.text or "Кто рядом" in r.text or "Who is here" in r.text)
        and ("data-clan-hall-presence-count=" in r.text)
        and ("data-clan-hall-assault=" in r.text)
        and ("data-clan-hall-heal=" in r.text)
        and (
            'data-clan-hall-need-scroll="1"' in r.text
            or 'data-clan-hall-assault="0"' not in r.text
        )
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/airship_station", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/airship_station wallet",
        r.status_code == 200
        and 'data-building-key="airship_station"' in r.text
        and ("В кармане" in r.text or "Wallet" in r.text)
        and (
            "data-airship-affordable=" in r.text
            or "data-airship-wallet=" in r.text
            or "data-airship-any-affordable=" in r.text
            or 'data-airship-station="1"' in r.text
        )
        and ("data-airship-routes=" in r.text)
        and ("data-airship-can-board=" in r.text)
        and (
            'data-airship-route-deferred="1"' in r.text
            or 'data-airship-can-board="1"' in r.text
            or 'data-airship-any-affordable="0"' in r.text
        )
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    if (
        'data-airship-route-deferred="1"' in r.text
        or 'data-airship-any-affordable="0"' in r.text
        or 'data-airship-routes-empty=' in r.text
    ):
        report.add(
            "airship deferred/short recovery",
            "data-airship-recovery=" in r.text,
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
        report.add(
            "quest locked recovery CTA",
            'data-quest-locked="1"' in r.text and ("quest_recovery" in r.text or "/world" in r.text),
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
        report.add(
            "quests progress markers",
            ("data-quest-progress=" in r.text) and ("data-quest-ready=" in r.text),
        )
        report.add(
            "quests summary counts",
            ("data-quest-summary=" in r.text)
            and ("data-quest-available=" in r.text)
            and ("data-quest-active=" in r.text)
            and ("data-quest-ready-count=" in r.text)
            and ("data-quest-locked=" in r.text),
        )
        r_hud = s.get(f"{BASE}/world", timeout=TIMEOUT)
        report.add(
            "quest HUD chip after journal",
            r_hud.status_code == 200
            and (("data-quest-chip=" in r_hud.text) or ("nl-quest-chip" in r_hud.text)),
            f"url={r_hud.url}",
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
        r.status_code == 200
        and ('data-library-handbook="1"' in r.text)
        and ("Справочник Пепельной Завесы" in r.text or "Ashen Veil handbook" in r.text)
        and ('data-landmark-inside="1"' in r.text)
        and ('data-library-next="1"' in r.text),
        f"url={r.url}",
    )
    if r.status_code == 200:
        report.add(
            "library covers Assault and quest chain",
            (("PvP на клетке" in r.text) or ("Cell PvP" in r.text))
            and ("Цепь:" in r.text or "Приманка →" in r.text or "Chain:" in r.text or "Bait →" in r.text),
        )
        report.add(
            "library covers Obelisk Law fatigue",
            (("Обелиск" in r.text) or ("Obelisk" in r.text))
            and (("Склонность" in r.text) or ("Alignment" in r.text))
            and (("Усталость" in r.text) or ("Fatigue" in r.text)),
        )
        report.add(
            "library covers heal scroll chip",
            ("Лечение" in r.text) or ("heal scroll" in r.text.lower()) or ("Heal" in r.text),
        )
        report.add(
            "library covers gear wear",
            ('data-library-gear-wear="1"' in r.text) and ("Сломано" in r.text or "Broken" in r.text),
        )

    r = s.get(f"{BASE}/city/buildings/magic_school", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/magic_school board",
        r.status_code == 200
        and 'data-building-key="magic_school"' in r.text
        and ("Учебный зал" in r.text or "Training hall" in r.text)
        and ("Очки характеристик" in r.text or "Stat points" in r.text or "nl-school-skill-board" in r.text)
        and ("data-school-unspent=" in r.text)
        and ("data-school-can-allocate=" in r.text)
        and ("data-school-can-allocate-stats=" in r.text)
        and ("data-school-can-allocate-skills=" in r.text)
        and (
            'data-school-spent="1"' in r.text
            or 'data-school-can-allocate="1"' in r.text
        )
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/military_school", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/military_school board",
        r.status_code == 200
        and 'data-building-key="military_school"' in r.text
        and ("Рукопашный" in r.text or "Unarmed" in r.text or "nl-school-skill-board" in r.text)
        and ("data-school-board=" in r.text)
        and ("data-school-can-allocate=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/general_school", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/general_school board",
        r.status_code == 200
        and 'data-building-key="general_school"' in r.text
        and ("Смолокур" in r.text or "Tar Smith" in r.text or "Лекар" in r.text or "nl-school-skill-board" in r.text)
        and ("data-school-unspent=" in r.text)
        and ("data-school-can-allocate-stats=" in r.text)
        and ("data-school-can-allocate-skills=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
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
        r.status_code == 200
        and 'data-building-key="temple"' in r.text
        and ("обряд" in r.text.lower() or "rite" in r.text.lower())
        and ('data-temple-injury="' in r.text)
        and ("data-temple-wallet=" in r.text)
        and ("data-temple-light=" in r.text)
        and ("data-temple-rite-ready=" in r.text)
        and ("data-temple-can-afford=" in r.text)
        and (
            'data-temple-no-light="1"' in r.text
            or 'data-temple-rite-ready="1"' in r.text
            or 'data-temple-injury="0"' in r.text
            or "temple_recovery" in r.text
        )
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/city/buildings/bank", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/bank",
        r.status_code == 200
        and 'data-building-key="bank"' in r.text
        and ("Сейф" in r.text or "vault" in r.text.lower())
        and ("Ячейка" in r.text or "locker" in r.text.lower())
        and ("data-bank-locker=" in r.text)
        and ("data-bank-wallet=" in r.text)
        and ("data-bank-vm=" in r.text)
        and ("data-bank-can-deposit=" in r.text)
        and ("data-bank-can-withdraw=" in r.text)
        and ("data-bank-can-store=" in r.text)
        and ("data-bank-can-retrieve=" in r.text)
        and ("data-bank-item-options=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    if 'data-bank-wallet-empty="1"' in r.text:
        report.add(
            "bank empty wallet recovery",
            "data-bank-recovery=" in r.text,
            f"url={r.url}",
        )
    if 'data-bank-vault-empty="1"' in r.text:
        report.add(
            "bank empty vault recovery",
            "data-bank-recovery=" in r.text,
            f"url={r.url}",
        )
    r = s.get(f"{BASE}/city/buildings/souvenir_shop", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/souvenir_shop",
        r.status_code == 200
        and 'data-building-key="souvenir_shop"' in r.text
        and ("Приманка" in r.text or "bait" in r.text.lower())
        and ("в сумке:" in r.text or "in bag:" in r.text)
        and ("data-souvenir-wallet=" in r.text)
        and ("data-souvenir-affordable=" in r.text)
        and ("data-souvenir-any-affordable=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/auction", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/auction treasury",
        r.status_code == 200
        and 'data-building-key="auction"' in r.text
        and ("сейф" in r.text.lower() or "vault" in r.text.lower() or "NV" in r.text)
        and ("Лавка" in r.text or "Shop" in r.text or "/shop" in r.text)
        and ("data-auction-wallet=" in r.text)
        and ("data-auction-vault=" in r.text)
        and ("data-auction-vm=" in r.text)
        and ('data-auction-lots="deferred"' in r.text)
        and ('data-auction-lots-deferred="1"' in r.text)
        and ('data-auction-can-list="0"' in r.text)
        and ('data-auction-can-bid="0"' in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/dealer_house", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/dealer_house buyback",
        r.status_code == 200
        and 'data-building-key="dealer_house"' in r.text
        and ("data-dealer-buyback-total=" in r.text)
        and ("data-dealer-offer-lines=" in r.text)
        and ("data-dealer-wallet=" in r.text)
        and ("data-dealer-can-sell=" in r.text)
        and ('data-landmark-inside="1"' in r.text)
        and ("Скупщик" in r.text or "Ash Buyer" in r.text or "junk_dealer" in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/obelisk", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/obelisk",
        r.status_code == 200
        and 'data-building-key="obelisk"' in r.text
        and ("Привязать" in r.text or "Bind" in r.text)
        and ("data-obelisk-bound=" in r.text)
        and ("data-obelisk-wallet=" in r.text)
        and ("data-obelisk-can-recall=" in r.text)
        and ("data-obelisk-can-bind=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )

    ok_main_tav, detail_main_tav = click_hotspot(s, "go_main")
    report.add("return main before tavern fatigue", ok_main_tav, detail_main_tav)
    ok_arena, d_arena = click_hotspot(s, "arena")
    report.add("enter arena hotspot", ok_arena, d_arena)
    r = s.get(f"{BASE}/arena", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /arena lobby after entry",
        r.status_code == 200
        and "nl-arena-frame" in r.text
        and ("data-arena-vitals=" in r.text)
        and ("data-arena-hp=" in r.text)
        and ("data-arena-mp=" in r.text)
        and ("data-arena-apps=" in r.text)
        and ("data-arena-room-accessible=" in r.text)
        and ("A character is required" not in r.text),
        f"url={r.url}",
    )
    if 'data-arena-recent-empty="1"' in r.text:
        report.add(
            "arena recent empty Duels recovery",
            'ft=1' in r.text or "/arena" in r.text,
            f"url={r.url}",
        )
    if 'data-arena-room-locked="1"' in r.text:
        report.add(
            "arena locked room City recovery",
            'data-arena-recovery="city"' in r.text,
            f"url={r.url}",
        )
    if 'data-arena-apps-empty="1"' in r.text:
        report.add(
            "arena apps empty City recovery",
            'data-arena-recovery="city"' in r.text,
            f"url={r.url}",
        )
    r = s.get(f"{BASE}/city/buildings/tavern", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/tavern fatigue copy",
        r.status_code == 200
        and 'data-building-key="tavern"' in r.text
        and ("устал" in r.text.lower() or "fatigue" in r.text.lower())
        and ("data-tavern-vitals=" in r.text)
        and ("data-tavern-ready=" in r.text)
        and ("data-tavern-hp=" in r.text)
        and ("data-tavern-mp=" in r.text)
        and (
            'data-tavern-full="1"' in r.text
            or 'data-tavern-ready="1"' in r.text
        ),
        f"url={r.url}",
    )
    if 'data-tavern-full="1"' in r.text:
        report.add(
            "tavern full World recovery",
            'data-tavern-recovery="world"' in r.text,
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
        and ("склонност" in r.text.lower() or "alignment" in r.text.lower())
        and ("восточн" in r.text.lower() or "east gate" in r.text.lower())
        and ("data-law-wallet=" in r.text)
        and ("data-law-alignment=" in r.text)
        and ("data-law-first-pledge=" in r.text)
        and ("data-law-pledge-mode=" in r.text)
        and ("data-law-can-afford=" in r.text)
        and ("data-law-choice-ready=" in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add(
        "alignment chip on Law Quarter",
        (("Склонность?" in r.text) or ("nl-alignment-chip" in r.text) or ("Alignment?" in r.text))
        and ("data-alignment-chip=" in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/prison", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/prison",
        r.status_code == 200
        and 'data-building-key="prison"' in r.text
        and ("Обитель Закона" in r.text or "Law Abode" in r.text or "law_abode" in r.text)
        and ('data-prison="1"' in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )
    r = s.get(f"{BASE}/city/buildings/gallows", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/gallows east hint",
        r.status_code == 200
        and 'data-building-key="gallows"' in r.text
        and ("восточн" in r.text.lower() or "east gate" in r.text.lower())
        and ('data-gallows="1"' in r.text)
        and ('data-gallows-east="1"' in r.text)
        and ('data-landmark-inside="1"' in r.text),
        f"url={r.url}",
    )

    ok_east, d_east = click_hotspot(s, "east_gate")
    report.add("travel east_gate", ok_east, d_east)
    if ok_east:
        r = s.get(f"{BASE}/world", timeout=TIMEOUT)
        outdoorish = ("Пепельный Берег" in r.text) or ("nl-world-map" in r.text) or ("available-actions" in r.text)
        report.add("outdoor after east_gate", r.status_code == 200 and outdoorish, f"{r.status_code}")
        ok_enter, d_enter = enter_building(s)
        report.add("enter city after east_gate", ok_enter, d_enter)
        r = s.get(f"{BASE}/world", timeout=TIMEOUT)
        keys = sorted(parse_hotspot_forms(r.text))
        report.add(
            "law quarter after east re-enter",
            "law_abode" in keys or "east_gate" in keys or "prison" in keys,
            f"keys={keys[:8]}",
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
    banned = ["Wear", "Properties", "Requirements", "Inventory mass", "Equipment Sets", "Transfer", "Set name"]
    found_en = [w for w in banned if w in r.text]
    report.add("inventory no English chrome", not found_en, f"found={found_en}")
    report.add(
        "inventory equipment set name field",
        ("data-equipment-set-name=" in r.text) and (("Имя комплекта" in r.text) or ("Set name" not in r.text)),
        f"url={r.url}",
    )
    report.add(
        "inventory player-sell deferred",
        'data-inventory-player-sell="deferred"' in r.text,
        f"url={r.url}",
    )
    report.add(
        "inventory junk hint or link",
        ("Скупщику:" in r.text) or ("Junk buyer:" in r.text),
        f"url={r.url}",
    )
    report.add(
        "inventory junk NV estimate",
        ("data-inventory-junk-total=" in r.text) or ("до " in r.text and "NV" in r.text) or ("up to" in r.text),
        f"url={r.url}",
    )
    report.add(
        "inventory mass/slot capacity",
        ("data-inventory-mass=" in r.text) and ("data-inventory-slots=" in r.text),
        f"url={r.url}",
    )
    report.add(
        "inventory durability markers",
        ("data-inventory-broken=" in r.text) or ("nl-durability-bar" in r.text),
        f"url={r.url}",
    )
    if 'data-equipment-sets-empty="1"' in r.text:
        report.add(
            "inventory empty equipment-sets recovery",
            'data-inventory-recovery="shop"' in r.text,
            f"url={r.url}",
        )

    r = s.get(f"{BASE}/character/licenses", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /character/licenses",
        r.status_code == 200 and ("data-licenses-empty=" in r.text or "nl-profile-license-list" in r.text),
        f"url={r.url}",
    )
    if 'data-licenses-empty="1"' in r.text:
        report.add(
            "licenses empty Shop recovery",
            'data-licenses-recovery="shop"' in r.text,
            f"url={r.url}",
        )

    r = s.get(f"{BASE}/shop", timeout=TIMEOUT)
    banned_shop = ["You carry", "Shop funds", "Refresh to buy", "There are no items", "Valid for", "(quantity:"]
    found_shop = [w for w in banned_shop if w in r.text]
    report.add("shop no English chrome", not found_shop, f"found={found_shop}")
    r = s.get(f"{BASE}/shop?mode=sell", timeout=TIMEOUT)
    found_sell = [w for w in ["(quantity:", "Durability "] if w in r.text]
    report.add("shop sell no English chrome", not found_sell, f"found={found_sell}")

    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add("locale switcher", ("RU" in r.text and "EN" in r.text) or "/locales" in r.text)
    report.add(
        "chat tools deferred markers",
        r.status_code == 200
        and 'nl-chat-tool--disabled' in r.text
        and 'data-chat-tools-deferred="1"' in r.text
        and (
            "Пока недоступно в этом релизе." in r.text
            or "Not available in this release yet." in r.text
        ),
        f"url={r.url}",
    )
    if 'data-chat-empty="1"' in r.text:
        report.add(
            "compact chat empty recovery",
            'data-chat-recovery="world"' in r.text,
            f"url={r.url}",
        )
    if 'data-presence-empty="1"' in r.text:
        report.add(
            "presence empty World recovery",
            'data-presence-recovery="world"' in r.text,
            f"url={r.url}",
        )

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
        bait_chip_ok = (("Приманка:" in r.text) or ("nl-bait-chip" in r.text)) and (
            "data-bait-qty=" in r.text
        )
        report.add("outdoor bait chip", bait_chip_ok)
        if 'data-bait-qty="0"' in r.text or "data-bait-qty='0'" in r.text:
            report.add(
                "outdoor empty bait recovery",
                'data-bait-recovery="city"' in r.text or "data-bait-recovery='city'" in r.text,
            )
        if "nl-obelisk-chip" in r.text or "data-obelisk-chip-affordable=" in r.text:
            report.add(
                "outdoor obelisk chip affordability",
                ("data-obelisk-chip-affordable=" in r.text) or ("nl-obelisk-chip-form" in r.text),
            )
            if 'data-obelisk-chip-affordable="0"' in r.text:
                report.add(
                    "outdoor short obelisk recovery",
                    'data-obelisk-recovery="city"' in r.text,
                )
        ok_enter_w, d_enter_w = enter_building(s)
        report.add("enter city after west_gate", ok_enter_w, d_enter_w)
        r = s.get(f"{BASE}/world", timeout=TIMEOUT)
        keys = sorted(parse_hotspot_forms(r.text))
        report.add(
            "central square after west re-enter",
            "west_gate" in keys or "hospital" in keys or "tavern" in keys,
            f"keys={keys[:8]}",
        )

    failed = report.failed
    print("\n=== SUMMARY ===")
    print(f"passed={len(report.checks) - len(failed)} failed={len(failed)} total={len(report.checks)}")
    for c in failed:
        print(f"  - {c.name}: {c.detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
