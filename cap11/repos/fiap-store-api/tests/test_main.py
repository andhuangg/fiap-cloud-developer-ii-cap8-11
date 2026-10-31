from fastapi.testclient import TestClient
from main import app

cliente = TestClient(app)

def test_health():
    r = cliente.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"

def test_ready():
    assert cliente.get("/ready").status_code == 200

def test_produtos():
    r = cliente.get("/produtos")
    assert r.status_code == 200
    assert r.json()[0]["nome"] == "Teclado"

def test_versao():
    r = cliente.get("/versao")
    assert r.status_code == 200
    assert "versao" in r.json()

def test_categorias():
    r = cliente.get("/categorias")
    assert r.status_code == 200
    assert len(r.json()) == 2
