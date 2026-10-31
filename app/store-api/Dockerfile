# ---------- Stage 1: build das dependencias ----------
FROM python:3.12-slim AS builder

WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# ---------- Stage 2: imagem final ----------
FROM python:3.12-slim AS runtime

# usuario nao-root com UID fixo (importante para Pod Security Admission)
RUN groupadd --gid 10001 appuser \
 && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin appuser

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_ENV=dev

WORKDIR /app
COPY --chown=10001:10001 main.py .

USER 10001
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
