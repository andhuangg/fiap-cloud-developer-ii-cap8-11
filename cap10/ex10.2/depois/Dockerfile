# Dockerfile endurecido: store-api:1.1
# ---------- estagio 1: build ----------
# Builder com o MESMO Python da imagem final (Debian 12 -> /usr/bin/python3.11).
# Se o builder fosse python:3.12-slim (/usr/local/bin/python3.12), os symlinks do venv
# apontariam para um interpretador que nao existe no distroless.
FROM debian:12-slim AS builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-venv \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y pip setuptools wheel || true     # nao leva o instalador para a imagem final

# ---------- estagio 2: runtime ----------
# distroless: sem shell, sem apt, sem coreutils. So o interpretador e libs.
FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=65532:65532 main.py .
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
# UID numerico: o kubelet consegue validar runAsNonRoot sem ler /etc/passwd
USER 65532:65532
EXPOSE 8000
# forma exec: o Python e o PID 1 e recebe SIGTERM direto
ENTRYPOINT ["/opt/venv/bin/python3", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
