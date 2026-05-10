# syntax=docker/dockerfile:1

FROM python:3.12-alpine AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# hadolint ignore=DL3018,DL3002
RUN apk add --no-cache bash curl docker-cli \
    && mkdir -p /workspace

WORKDIR /workspace
COPY platform/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip==24.2 \
    && pip install --no-cache-dir -r /tmp/requirements.txt

EXPOSE 18081

CMD ["uvicorn", "api:app", "--app-dir", "/workspace/platform", "--host", "0.0.0.0", "--port", "18081"]
