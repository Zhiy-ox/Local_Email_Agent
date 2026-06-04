# Dockerfile — the web layer only (api_server.py + the ui/ web app).
#
# MLX, the Mail/Calendar AppleScript worker, and real Calendar writes run
# NATIVELY on the macOS host — they cannot run in a Linux container. This image
# serves the UI and the LLM-backed JSON endpoints, and reaches the host's MLX
# server at host.docker.internal:8080 (see docker-compose.yml).
FROM python:3.12-slim

WORKDIR /app

# Only third-party dependency is `requests`; everything else is stdlib.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# App code + UI. AppleScript scripts and the worker are intentionally excluded
# (host-only); see .dockerignore.
COPY api_server.py llm_client.py ./
COPY ui/ ./ui/

# Bind to 0.0.0.0 so the published port is reachable from the host.
# Defaults point at MLX running natively on the host.
ENV BIND_HOST=0.0.0.0 \
    PORT=8000 \
    LLM_BACKEND=mlx \
    LLM_BASE_URL=http://host.docker.internal:8080 \
    LLM_MODEL=mlx-community/Llama-3.2-3B-Instruct-4bit

EXPOSE 8000

CMD ["python", "api_server.py"]
