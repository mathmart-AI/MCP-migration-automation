# ==============================================================================
# Axon.MCP.Server — "Dumb Backend" Docker Image
# Optimized for the Zero Egress architecture (Go Proxy → Python Backend)
# ==============================================================================

# --------------- Build Stage ---------------
FROM python:3.12-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System deps required for compilation (psycopg2-binary, gitpython, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create isolated venv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python deps first (layer caching)
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt

# --------------- Production Stage ---------------
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# ── Default env vars for Pydantic Settings (required fields) ──────────────────
# These provide sensible "stub" values so the FastAPI app can boot without
# external configuration.  Override them at runtime via `docker run -e ...`.
ENV DATABASE_URL="sqlite+aiosqlite://" \
    GITLAB_TOKEN="dummy_gitlab_token" \
    API_SECRET_KEY="dummy_api_secret_key_for_local_dev" \
    JWT_SECRET_KEY="dummy_jwt_secret_key_64chars_padding_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    AUTH_ENABLED="false" \
    MCP_AUTH_ENABLED="false" \
    ADMIN_API_KEY="" \
    ADMIN_PASSWORD="" \
    API_HOST="0.0.0.0" \
    API_PORT="8000" \
    MCP_TRANSPORT="http" \
    MCP_HTTP_HOST="0.0.0.0" \
    MCP_HTTP_PORT="8000" \
    REDIS_CACHE_ENABLED="false" \
    ENVIRONMENT="local" \
    DEBUG="false" \
    LOG_LEVEL="INFO"

# Minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy venv from builder
COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# Non-root user for security
RUN useradd -m -u 1000 axon && \
    chown -R axon:axon /app

# Copy application source
COPY --chown=axon:axon . /app/

# Create cache directory
RUN mkdir -p /app/cache && chown -R axon:axon /app/cache

USER axon

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1

CMD ["uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
