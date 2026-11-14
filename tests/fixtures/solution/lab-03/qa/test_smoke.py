import os
import requests

BASE = os.environ.get("QA_BASE_URL", "http://localhost:8080")


def test_health():
    assert requests.get(f"{BASE}/health", timeout=5).text.strip() == "ok"


def test_ready():
    assert requests.get(f"{BASE}/ready", timeout=5).json()["ready"] is True


def test_visits_counts_up():
    first = requests.get(f"{BASE}/visits", timeout=5).json()["visits"]
    second = requests.get(f"{BASE}/visits", timeout=5).json()["visits"]
    assert second == first + 1


def test_unknown_route_is_404():
    assert requests.get(f"{BASE}/nope", timeout=5).status_code == 404


def test_price_without_partner_is_502():
    assert requests.get(f"{BASE}/price/MK-II", timeout=10).status_code == 502
