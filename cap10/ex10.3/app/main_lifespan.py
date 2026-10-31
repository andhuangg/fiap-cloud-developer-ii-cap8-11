# main.py: store-api com shutdown gracioso (lifespan), secao 10.10.2
import asyncio, os, socket
from contextlib import asynccontextmanager
from fastapi import FastAPI, Response

PRONTO = True

@asynccontextmanager
async def lifespan(app: FastAPI):
    # ----- startup -----
    print("startup: pronto para receber trafego", flush=True)
    yield
    # ----- shutdown (roda ao receber SIGTERM) -----
    global PRONTO
    PRONTO = False                  # /ready passa a responder 503
    print("SIGTERM recebido: /ready agora responde 503, drenando...", flush=True)
    await asyncio.sleep(5)          # drena o que ja esta em voo
    print("shutdown concluido", flush=True)

app = FastAPI(title="FIAP Store API", lifespan=lifespan)

@app.get("/health")
def health():
    return {"status": "ok", "host": socket.gethostname()}

@app.get("/ready")
def ready(response: Response):
    if not PRONTO:
        response.status_code = 503
        return {"status": "shutting-down"}
    return {"status": "ready"}

@app.get("/produtos")
def produtos():
    return [{"id": 1, "nome": "Teclado", "preco": 199.9}]

@app.get("/info")
def info():
    return {"env": os.getenv("APP_ENV", "dev"), "pod": socket.gethostname()}
