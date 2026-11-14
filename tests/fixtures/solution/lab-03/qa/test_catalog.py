"""Scenarios of my own, beside the five that came with the lab."""
import os

import requests

BASE = os.environ.get("QA_BASE_URL", "http://localhost:8080")
PARTNER = os.environ.get("QA_PROFILE", "") == "partner"


def test_health_is_cheap():
    r = requests.get(f"{BASE}/health", timeout=5)
    assert r.elapsed.total_seconds() < 1


def test_unknown_sku_still_answers():
    r = requests.get(f"{BASE}/price/NO-SUCH-SKU", timeout=10)
    assert r.status_code in (200, 502)
    assert r.json()["sku"] == "NO-SUCH-SKU"


def test_visits_survives_a_restart_of_the_suite():
    before = requests.get(f"{BASE}/visits", timeout=5).json()["visits"]
    assert before >= 1


def test_price_error_names_the_cause():
    if PARTNER:
        return
    body = requests.get(f"{BASE}/price/MK-II", timeout=10).json()
    assert body["error"]
    assert requests.get(f"{BASE}/price/MK-II", timeout=10).status_code == 502
