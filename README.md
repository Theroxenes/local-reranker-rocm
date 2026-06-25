# local-reranker-rocm

A local reranker service with a Jina compatible API.  
Forked from olafgeibig/local-reranker to add ROCm support.

# Overview

This project provides a FastAPI-based web service that implements a reranking API endpoint (`/v1/rerank`) compatible with the [Jina AI Rerank API](https://jina.ai/rerank/). It allows you to host a reranking model entirely on your own infrastructure for enhanced privacy and performance.

# Features

*   **Jina Compatible API**: Implements `/v1/rerank` endpoint structure
*   **Local Hosting**: Run reranker model entirely on your own infrastructure
*   **Multiple Backends**: Supports both PyTorch and MLX backends for optimal performance
*   **Sentence Transformers**: Uses powerful `sentence-transformers` library for PyTorch backend
*   **Configurable Model**: Easily switch between different reranker models and backends
*   **Modern FastAPI**: Built using modern FastAPI features like `lifespan` for resource management
*   **Modern Dependencies**: Updated to latest stable versions with sensible minimum requirements

# Requirements

*   Python 3.12+
*   [uv](https://github.com/astral-sh/uv) (for installation and package management - recommended)
*   Sufficient RAM and compute resources (CPU or GPU) depending on the chosen reranker model

## Backend-Specific Requirements

**PyTorch Backend:**
*   PyTorch 2.5+ (automatically installed)
*   ROCm support for GPU acceleration (optional)

**ROCm Backend:**

# Installation

```bash
# Clone the repository
git clone https://github.com/theroxenes/local-reranker-rocm.git
cd local-reranker-rocm

# Create virtual environment
uv venv
source .venv/bin/activate

# Install dependencies
uv pip install -e ".[dev]"
```

# Usage

The CLI supports both modern subcommands and legacy arguments for backward compatibility.

## Modern CLI (Recommended)

```bash
# Start server with subcommand
cli serve --backend <backend_type> [options]

# Show configuration
cli config show
```

## Legacy CLI (Backward Compatible)

```bash
# Old-style arguments still work
cli --backend <backend_type> --model <model> --host <host> --port <port>
```

## Available Backends

*   `pytorch`: PyTorch-based reranker (default, cross-platform)

## Command Options

*   `--backend`: Backend type to use (default: pytorch)
*   `--model`: Model name to use (overrides reranker default)
*   `--host`: Host to bind server to (default: 0.0.0.0)
*   `--port`: Port to bind server to (default: 8010)
*   `--log-level`: Uvicorn log level (debug, info, warning, error, critical; default: info)
*   `--reload`: Enable auto-reload for development

## Examples

**PyTorch Backend (default):**

```bash
cli serve --backend pytorch --model BAAI/bge-reranker-v2-m3
```

**Development Mode:**

```bash
cli serve --backend pytorch --reload --log-level debug
```

**Configuration Management:**

```bash
cli config show
```

# Docker Deployment (ROCm GPU)

## Build

```bash
docker build -t local-reranker-rocm .
```

# API Usage

Once the server is running, you can send requests to the `/v1/rerank` endpoint. Here's an example using `curl`:

```bash
curl -X POST "http://localhost:8010/v1/rerank" \
     -H "Content-Type: application/json" \
     -d '{
           "model": "BAAI/bge-reranker-v2-m3", 
           "query": "What are the benefits of using FastAPI?", 
           "documents": [
             "FastAPI is a modern, fast (high-performance) web framework for building APIs with Python 3.7+ based on standard Python type hints.",
             "Django is a high-level Python Web framework that encourages rapid development and clean, pragmatic design.",
             "The key features are: Fast, Fast to code, Fewer dependencies, Intuitive, Easy, Short, Robust, Standards-based.",
             "Flask is a micro web framework written in Python."
           ],
           "top_n": 3,
           "return_documents": true
         }'
```

## Parameters

*   `model`: (Currently ignored by API, uses the configured default) The name of the reranker model
*   `query`: The search query string
*   `documents`: A list of strings or dictionaries (`{"text": "..."}`) to be reranked against the query
*   `top_n`: (Optional) The maximum number of results to return
*   `return_documents`: (Optional, default `false`) Whether to include document text in results

# Development

## Setting Up Development Environment

1. **Clone the repository:**
    ```bash
    git clone https://github.com/theroxenes/local-reranker-rocm.git
    cd local-reranker-rocm
    ```

2. **Create a virtual environment:**
    ```bash
    uv venv
    source .venv/bin/activate
    ```

3. **Install development dependencies:**
    ```bash
    uv pip install -e ".[dev]"
    ```

4. **Verify installation:**
    ```bash
    # Test CLI works
    cli config show
    
    # Test server starts
    cli serve --backend pytorch --help
    ```

## Running Tests

Tests are implemented using `pytest`. To run tests:

```bash
# Ensure virtual environment is active
python -m pytest

# Or using uv run
uv run pytest

# Run specific test categories
uv run pytest -m "not integration"  # Skip integration tests
uv run pytest -m "integration"       # Only integration tests
uv run pytest -m "slow"            # Only slow tests
```

## Code Quality

The project uses modern development tools:

```bash
# Run linting
uv run ruff check

# Run type checking
uv run mypy src/

# Run both
uv run ruff check && uv run mypy src/
```

# Troubleshooting

## GPU not detected / `No HIP GPUs available`

This is the most common setup issue and almost always comes down to **render
group membership**. ROCm compute requires the container process to be in the
group that owns `/dev/kfd` and the render node — and that group's numeric GID
**varies by host**, so the default in `docker-compose.yml` is unlikely to be
correct for your system. There is no universal value.

### Fix, in order

**1. Confirm the device nodes exist on the host:**
```bash
ls -l /dev/kfd /dev/dri/renderD*
```
You should see `/dev/kfd` and at least one `/dev/dri/renderD128` (or similar).
If `/dev/kfd` is missing, the host's `amdgpu` driver/ROCm isn't set up — fix
that first; this image can't create the device.

**2. Find your render group's GID:**
```bash
getent group render | cut -d: -f3
```
Common values: **104** (Debian/Ubuntu bare metal), **993** (some Proxmox
unprivileged LXCs, via idmap), **109/110** (other distros). Use whatever
*your* host reports — not the example in the compose file.

> **Proxmox LXC note:** inside an *unprivileged* LXC the render GID you see
> (and must use here) is the **container-side** value after idmap translation
> — often different from the host's GID. Run the command above *inside the
> container's environment* / on the LXC, not on the Proxmox host, and use that
> number.

**3. Set `group_add` in `docker-compose.yml` to that GID:**
```yaml
    group_add:
      - "104"   # <-- your value from step 2
```

**4. Verify GPU access before wiring anything else:**
```bash
docker run --rm \
  --device /dev/kfd --device /dev/dri/renderD128 \
  --group-add <YOUR_GID> \
  ghcr.io/theroxenes/local-reranker-rocm:latest \
  python -c "import torch; print(torch.cuda.is_available()); print(torch.randn(10).to('cuda').sum())"
```

Expected: `True` followed by a tensor (e.g. `tensor(3.97, device='cuda:0')`).
- `True` + tensor → GPU access works; you're done.
- `True` then an error/no tensor → torch sees the GPU but can't run a kernel
  on your architecture. RDNA2/older cards may need
  `-e HSA_OVERRIDE_GFX_VERSION=10.3.0` (RDNA2) or `11.0.0` (RDNA3). RDNA4
  (gfx1201) works without an override on the ROCm build this image ships.
- `No HIP GPUs available` → wrong `group_add` GID (back to step 2), or the
  device nodes aren't being passed (check the `--device` flags).

## Wrong torch build

This image ships ROCm torch from its base image. To confirm:
```bash
docker run --rm --entrypoint /opt/venv/bin/pip \
  ghcr.io/theroxenes/local-reranker-rocm:latest show torch
```
The version must contain `+rocm` (e.g. `2.10.0+rocm7.2.4`). If it shows a plain
or `+cu` (CUDA) version, the build picked up the wrong torch — please open an
issue with the output.

## Container starts but `/health` returns 503

`/health` returns **503** when the reranker model failed to load (and **200**
when ready). A 503 means the model didn't load — check the container logs for
the startup error:
```bash
docker logs <container> 2>&1 | grep -i -A20 "loading reranker\|fatal\|error"
```
Most common cause: a model that requires custom `trust_remote_code` which is
incompatible with the bundled `transformers` version. The default model
(`BAAI/bge-reranker-v2-m3`) is a stock cross-encoder and avoids this. If you
set `RERANKER_MODEL_NAME` to a model with custom modeling code (e.g. some
`jina-reranker` variants) and see an `ImportError` from the model's remote
code, switch to a stock-architecture reranker or pin `transformers` to a
version that model supports.

## Model re-downloads on every restart

The model is cached under `HF_HOME` (set to `/cache` in the provided compose)
and persisted via the `hf-cache` named volume. If the model re-downloads every
time, confirm the volume is mounted at the same path as `HF_HOME`:
```yaml
    environment:
      - HF_HOME=/cache
    volumes:
      - hf-cache:/cache
```

## Choosing / changing the model

The model is set at deploy time via `RERANKER_MODEL_NAME` — no rebuild needed.
Use a **stock cross-encoder** (loads through `sentence-transformers` with no
custom remote code) for best compatibility. Known-good default:
`BAAI/bge-reranker-v2-m3` (multilingual, ~568M params). Models that ship custom
`trust_remote_code` can break against the bundled `transformers` version; see
the `/health` 503 section above.

**Model download fails:**
```bash
# Check internet connection
# Try manual download
huggingface-cli download BAAI/bge-reranker-v2-m3
```

# Environment Variables

The application uses pydantic-settings for configuration management. You can set the following environment variables to override defaults:

```bash
# Custom model name
export RERANKER_MODEL_NAME=custom-model

# Custom host and port
export RERANKER_HOST=0.0.0.0
export RERANKER_PORT=8080

# Enable debug logging
export RERANKER_LOG_LEVEL=debug

# Enable auto-reload
export RERANKER_RELOAD=true
```

**Note**: Using the CLI command line options is recommended over environment variables for clarity.

# Project Structure

```
local-reranker/
├── src/local_reranker/
│   ├── __init__.py
│   ├── api.py                   # FastAPI application
│   ├── cli.py                   # Command line interface
│   ├── config.py                # Configuration management
│   ├── models.py                # Pydantic models
│   ├── reranker.py              # Base reranker interface (protocol)
│   ├── reranker_pytorch.py      # PyTorch implementation
│   ├── reranker_mlx.py          # MLX implementation
│   ├── batch_manager.py         # Batch size and document management
│   ├── batch_processor.py       # Shared batch processing logic
│   ├── result_aggregator.py     # Result aggregation and ordering
│   ├── streaming_processor.py   # Streaming result processing
│   ├── tokenization_cache.py    # Tokenization caching
│   └── utils.py                 # Utility functions
├── tests/                       # Test suite
├── pyproject.toml               # Project configuration
└── README.md                    # This file
```

# Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
