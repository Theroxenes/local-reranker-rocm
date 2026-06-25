FROM rocm/pytorch@sha256:4449f856653602317e4101a76fce599c7fcd58ccec2e539951fce5f73083179e
 
WORKDIR /app
 
# The ROCm torch in this base lives in the venv at /opt/venv (verified:
# `python -c "import torch,sys; print(sys.executable)"` -> /opt/venv/bin/python,
# torch 2.10.0+rocm7.2.4). Install the app into THAT venv so it sits alongside
# the existing ROCm torch — NOT into the system Python at /usr (which is
# externally-managed and has no torch).
ENV VENV=/opt/venv
 
# Install uv into the same venv.
RUN /opt/venv/bin/pip install --no-cache-dir uv
 
# Install runtime dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
 
# NOTE: original created a non-root appuser (uid 1000) here. Dropped for now —
# GPU access depends on the container process being in the `render` group
# (GID 993), supplied at runtime via --group-add / compose group_add. Get GPU
# working first, then re-add a hardened non-root user that is a member of 993.
 
# Expose port
EXPOSE 8010
 
# Copy project files
COPY pyproject.toml pyproject.toml
COPY README.md README.md
COPY src src
COPY uv.lock uv.lock
 
SHELL ["/bin/bash", "-c"]
 
# Install the app + deps into the venv that already holds ROCm torch.
# --python /opt/venv/bin/python targets that interpreter explicitly; --system
# resolved /usr (the externally-managed system Python with no torch) and failed.
# torch and mlx/mlx-lm have been removed from pyproject dependencies in this
# fork (torch comes from the base venv; mlx is Apple-only).
RUN /opt/venv/bin/uv pip install --python /opt/venv/bin/python -e .
RUN /opt/venv/bin/python -c "import torch; assert torch.version.hip is not None, f'Not a ROCm build: {torch.__version__}'; print(f'OK: torch {torch.__version__}, hip={torch.version.hip}')"
 
# Set environment variables. PATH puts /opt/venv/bin first so bare `python`
# (in ENTRYPOINT, CMD, HEALTHCHECK) resolves to the venv interpreter that has
# torch + the app — not the system /usr/bin/python.
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    RERANKER_HOST=0.0.0.0 \
    RERANKER_PORT=8010
 
# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8010/health')" || exit 1
 
# Default entrypoint - can be overridden
# Uses PyTorch backend (correct for ROCm; --backend mlx is Apple-Silicon only)
ENTRYPOINT ["python", "-m", "local_reranker.cli"]
CMD ["serve", "--backend", "pytorch", "--host", "0.0.0.0", "--port", "8010"]

