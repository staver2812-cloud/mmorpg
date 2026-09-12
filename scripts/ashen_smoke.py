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
        ("/arena", ["nl-arena", "Арена", "Дуэли"]),
        ("/city/buildings/tavern", ["data-building-key=\"tavern\"", "nl-city-landmark"]),
        ("/city/buildings/workshop", ["data-building-key=\"workshop\"", "nl-city-landmark"]),
        ("/city/buildings/hospital", ["data-building-key=\"hospital\"", "Лазарет", "hospital"]),
    ]:
        r = s.get(urljoin(BASE + "/", path.lstrip("/")), timeout=TIMEOUT)
        hit = any(n in r.text for n in needles)
        report.add(f"GET {path}", r.status_code == 200 and hit, f"{r.status_code} needles={hit}")
        time.sleep(0.1)

    ok, detail = click_hotspot(s, "go_forpost1")
    report.add("travel go_forpost1", ok, detail)
    r = s.get(f"{BASE}/city/buildings/city_hall", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/city_hall",
        r.status_code == 200 and 'data-building-key="city_hall"' in r.text,
        f"url={r.url}",
    )
    if r.status_code == 200:
        report.add("city_hall quest board", "Задания" in r.text or "/quests" in r.text)

    r = s.get(f"{BASE}/quests", timeout=TIMEOUT)
    report.add(
        "GET /quests",
        r.status_code == 200 and ("Пепельный дозор" in r.text or "Ashen Veil Quests" in r.text or "nl-quests" in r.text),
        f"{r.status_code}",
    )
    if r.status_code == 200:
        token = csrf_from(r.text) or token
        # accept first available quest (veil_tail_delivery is sort 5)
        r_acc = s.post(
            f"{BASE}/quests/veil_tail_delivery/accept",
            data={"authenticity_token": token},
            timeout=TIMEOUT,
            allow_redirects=True,
        )
        report.add(
            "POST accept veil_tail_delivery",
            r_acc.status_code in (200, 302) and ("принято" in r_acc.text.lower() or "accepted" in r_acc.text.lower() or "В работе" in r_acc.text or "In progress" in r_acc.text),
            f"{r_acc.status_code}",
        )

    ok_main, d1 = click_hotspot(s, "go_main")
    report.add("travel go_main", ok_main, d1)
    ok, detail = click_hotspot(s, "go_forpost3")
    report.add("travel go_forpost3", ok, detail)

    r = s.get(f"{BASE}/city/buildings/temple", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/temple",
        r.status_code == 200 and 'data-building-key="temple"' in r.text,
        f"url={r.url}",
    )

    r = s.get(f"{BASE}/city/buildings/bank", timeout=TIMEOUT, allow_redirects=True)
    report.add(
        "GET /city/buildings/bank",
        r.status_code == 200 and 'data-building-key="bank"' in r.text,
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

    r = s.get(f"{BASE}/shop", timeout=TIMEOUT)
    banned_shop = ["You carry", "Shop funds", "Refresh to buy", "There are no items"]
    found_shop = [w for w in banned_shop if w in r.text]
    report.add("shop no English chrome", not found_shop, f"found={found_shop}")

    r = s.get(f"{BASE}/world", timeout=TIMEOUT)
    report.add("locale switcher", ("RU" in r.text and "EN" in r.text) or "/locales" in r.text)

    ok, _ = click_hotspot(s, "go_main")
    report.add("return go_main", ok)
    r = s.get(f"{BASE}/city/buildings/temple", timeout=TIMEOUT, allow_redirects=True)
    gated = "/world" in r.url or 'data-building-key="temple"' not in r.text
    report.add("temple gated from main square", gated, f"url={r.url}")

    ok_gate, gate_detail = click_hotspot(s, "west_gate")
    report.add("travel west_gate", ok_gate, gate_detail)
    if ok_gate:
        r = s.get(f"{BASE}/world", timeout=TIMEOUT)
        outdoorish = ("Пепельный Берег" in r.text) or ("nl-world-map" in r.text) or ("available-actions" in r.text)
        report.add("outdoor after west_gate", r.status_code == 200 and outdoorish, f"{r.status_code}")

    failed = report.failed
    print("\n=== SUMMARY ===")
    print(f"passed={len(report.checks) - len(failed)} failed={len(failed)} total={len(report.checks)}")
    for c in failed:
        print(f"  - {c.name}: {c.detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
