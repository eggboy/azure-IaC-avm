# Build with uv. pyproject.toml + uv.lock pin the full transitive closure, so a
# rebuild from this directory is reproducible across machines.
FROM python:3.11.14-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PATH="/app/.venv/bin:$PATH"

# Pinned uv binary (matches the version used to generate uv.lock).
COPY --from=ghcr.io/astral-sh/uv:0.11.25 /uv /uvx /bin/

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies first as a cacheable layer; --locked fails if uv.lock is
# out of date with pyproject.toml.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-dev

COPY src ./src

EXPOSE 8080

CMD ["uvicorn", "src.server_multi_auth:app", "--host", "0.0.0.0", "--port", "8080"]
