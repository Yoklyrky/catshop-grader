from app import app


def test_health_again():
    assert app.test_client().get("/health").status_code == 200
