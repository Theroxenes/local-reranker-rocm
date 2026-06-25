# -*- coding: utf-8 -*-
"""local_reranker package.

A lightweight, local reranker API implementation.
"""

__version__ = "0.2.1"

from .cli import main
try:
    from .jina_mlx_reranker import JinaMLXReranker
except ModuleNotFoundError:
    JinaMLXReranker = None

__all__ = ["main", "JinaMLXReranker"]
