FROM python:3.11-slim AS builder

WORKDIR /app

# hadolint ignore=DL3013
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.11-slim AS production

# hadolint ignore=DL3005,DL3008
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Runtime deps are already installed (see builder's --user install below),
# so pip/setuptools/wheel and ensurepip's bundled wheels are never used here.
# Strip them instead of upgrading: their vendored copies (pip vendors its own
# msgpack; ensurepip bundles a setuptools wheel) carry CVEs that upgrading
# pip alone doesn't clear.
RUN python -m pip uninstall -y pip setuptools wheel 2>/dev/null; \
    rm -rf /usr/local/lib/python3.*/ensurepip \
           /usr/local/lib/python3.*/site-packages/pip* \
           /usr/local/lib/python3.*/site-packages/setuptools* \
           /usr/local/lib/python3.*/site-packages/wheel* \
           /usr/local/lib/python3.*/site-packages/_distutils_hack \
           /usr/local/lib/python3.*/site-packages/pkg_resources \
           /usr/local/bin/pip* \
           /usr/local/bin/wheel*

RUN groupadd -r appgroup && useradd -r -g appgroup -m appuser

WORKDIR /app

COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appgroup . .

ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8003/health')" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8003", "app:app"]
