# main.py
from fastapi import FastAPI, Response
import os, socket

VERSAO = "1.1"

app = FastAPI(title="FIAP Store API", version=VERSAO)
PRONTO = True

@app.get("/health")
def health():
    return {"status": "ok", "host": socket.gethostname()}

@app.get("/ready")
def ready(response: Response):
    if not PRONTO:
        response.status_code = 503
        return {"status": "starting"}
    return {"status": "ready"}

@app.get("/produtos")
def produtos():
    return [{"id": 1, "nome": "Teclado", "preco": 199.9}]

@app.get("/info")
def info():
    return {"env": os.getenv("APP_ENV", "dev"),
            "db_host": os.getenv("DB_HOST", "nao-configurado"),
            "pod": socket.gethostname()}

@app.get("/versao")
def versao():
    return {"versao": VERSAO, "pod": socket.gethostname()}

@app.get("/categorias")
def categorias():
    return [{"id": 1, "nome": "Perifericos"}, {"id": 2, "nome": "Monitores"}]
