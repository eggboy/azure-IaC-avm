# Reconstructed from `docker history eggboy/multi-auth-mcp:latest` so a rebuild
# from this directory produces a runtime-equivalent image. Pinned base + locked
# requirements.txt make the build reproducible across machines.
FROM python:3.11.14-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY src ./src

EXPOSE 8080

CMD ["uvicorn", "src.server_multi_auth:app", "--host", "0.0.0.0", "--port", "8080"]
