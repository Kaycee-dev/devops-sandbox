# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN python -m venv /opt/venv \
    && pip install --no-cache-dir --upgrade pip==24.2 \
    && pip install --no-cache-dir Flask==3.0.3

FROM python:3.12-slim AS runtime

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

RUN groupadd --system --gid 10001 sandbox \
    && useradd --system --uid 10001 --gid sandbox --home-dir /app --shell /usr/sbin/nologin sandbox \
    && mkdir -p /app \
    && chown -R sandbox:sandbox /app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=sandbox:sandbox app.py /app/app.py

USER sandbox
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2).read()"

CMD ["python", "app.py"]
