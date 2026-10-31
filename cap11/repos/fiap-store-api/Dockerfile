# store-api: multi-stage + distroless nonroot (capitulo 10)
FROM debian:12-slim AS builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-venv \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y pip setuptools wheel || true

FROM gcr.io/distroless/python3-debian12:nonroot
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=65532:65532 main.py .
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
USER 65532:65532
EXPOSE 8000
ENTRYPOINT ["/opt/venv/bin/python3", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
