"""
Pluggable LLM client for the Local Email Agent.

All callers should use:
    from llm_client import get_llm_client
    client = get_llm_client()
    reply = client.chat(messages, temperature=0.2)

Configuration (priority: env vars > config.json > defaults):
    LLM_BACKEND   one of: mlx, openai_compatible, openai, anthropic
    LLM_BASE_URL  base URL of the server (no trailing /v1/...)
    LLM_MODEL     model identifier passed to the backend
    LLM_API_KEY   optional bearer token (cloud backends)
    LLM_TIMEOUT   "<connect>,<read>" seconds, e.g. "10,180"

Defaults target an MLX (mlx-lm) server on localhost:
    backend = mlx
    base_url = http://127.0.0.1:8080
    model    = local
"""

import json
import os
from pathlib import Path
from typing import Optional

import requests


_CONFIG_PATH = Path(__file__).resolve().parent / "config.json"

DEFAULTS = {
    "backend": "mlx",
    "base_url": "http://127.0.0.1:8080",
    "model": "local",
    "api_key": "",
    "timeout": (10, 180),
}


def _load_file_config() -> dict:
    if not _CONFIG_PATH.exists():
        return {}
    try:
        with _CONFIG_PATH.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return data.get("llm", {}) if isinstance(data, dict) else {}
    except Exception:
        return {}


def _parse_timeout(raw) -> tuple:
    if isinstance(raw, (list, tuple)) and len(raw) == 2:
        return (float(raw[0]), float(raw[1]))
    if isinstance(raw, str) and "," in raw:
        a, b = raw.split(",", 1)
        return (float(a.strip()), float(b.strip()))
    return DEFAULTS["timeout"]


def _resolve_config() -> dict:
    file_cfg = _load_file_config()
    cfg = {**DEFAULTS, **file_cfg}

    if os.getenv("LLM_BACKEND"):
        cfg["backend"] = os.environ["LLM_BACKEND"].strip().lower()
    if os.getenv("LLM_BASE_URL"):
        cfg["base_url"] = os.environ["LLM_BASE_URL"].rstrip("/")
    if os.getenv("LLM_MODEL"):
        cfg["model"] = os.environ["LLM_MODEL"]
    if os.getenv("LLM_API_KEY"):
        cfg["api_key"] = os.environ["LLM_API_KEY"]
    if os.getenv("LLM_TIMEOUT"):
        cfg["timeout"] = _parse_timeout(os.environ["LLM_TIMEOUT"])
    else:
        cfg["timeout"] = _parse_timeout(cfg.get("timeout"))

    cfg["base_url"] = str(cfg["base_url"]).rstrip("/")
    return cfg


class LLMClient:
    """Base class. Subclasses implement chat()."""

    def __init__(self, base_url: str, model: str, api_key: str = "", timeout=(10, 180)):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key = api_key
        self.timeout = timeout

    def chat(self, messages: list[dict], temperature: float = 0.2) -> str:
        raise NotImplementedError


class OpenAICompatibleClient(LLMClient):
    """
    Works against any server that speaks the OpenAI Chat Completions wire format
    at <base_url>/v1/chat/completions. Covers mlx-lm, llama.cpp, LM Studio, vLLM,
    Ollama (when its OpenAI shim is enabled at /v1).
    """

    endpoint_path = "/v1/chat/completions"

    def chat(self, messages: list[dict], temperature: float = 0.2) -> str:
        url = self.base_url + self.endpoint_path
        payload = {"model": self.model, "temperature": temperature, "messages": messages}
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        r.raise_for_status()
        data = r.json()
        return data["choices"][0]["message"]["content"]


class MLXClient(OpenAICompatibleClient):
    """
    MLX via `python -m mlx_lm.server` exposes an OpenAI-compatible endpoint.
    Identical wire format; this subclass exists so config/logging can name it.
    """


class OpenAIClient(OpenAICompatibleClient):
    """OpenAI cloud. Defaults base_url to https://api.openai.com if blank/local."""

    def __init__(self, base_url: str, model: str, api_key: str = "", timeout=(10, 180)):
        if not base_url or base_url.startswith("http://127.") or base_url.startswith("http://localhost"):
            base_url = "https://api.openai.com"
        super().__init__(base_url, model, api_key, timeout)


class AnthropicClient(LLMClient):
    """Anthropic Messages API. Translates from OpenAI-style messages."""

    def chat(self, messages: list[dict], temperature: float = 0.2) -> str:
        if not self.api_key:
            raise RuntimeError("AnthropicClient requires LLM_API_KEY")
        base = self.base_url or "https://api.anthropic.com"
        url = base.rstrip("/") + "/v1/messages"

        system_parts = [m["content"] for m in messages if m.get("role") == "system"]
        convo = [
            {"role": m["role"], "content": m["content"]}
            for m in messages
            if m.get("role") in ("user", "assistant")
        ]
        payload = {
            "model": self.model,
            "max_tokens": 4096,
            "temperature": temperature,
            "messages": convo,
        }
        if system_parts:
            payload["system"] = "\n\n".join(system_parts)

        headers = {
            "Content-Type": "application/json",
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
        }
        r = requests.post(url, json=payload, headers=headers, timeout=self.timeout)
        r.raise_for_status()
        data = r.json()
        blocks = data.get("content", [])
        return "".join(b.get("text", "") for b in blocks if b.get("type") == "text")


_BACKENDS = {
    "mlx": MLXClient,
    "openai_compatible": OpenAICompatibleClient,
    "llamacpp": OpenAICompatibleClient,
    "ollama": OpenAICompatibleClient,
    "lmstudio": OpenAICompatibleClient,
    "openai": OpenAIClient,
    "anthropic": AnthropicClient,
}


_cached: Optional[LLMClient] = None


def get_llm_client(force_reload: bool = False) -> LLMClient:
    global _cached
    if _cached is not None and not force_reload:
        return _cached

    cfg = _resolve_config()
    cls = _BACKENDS.get(cfg["backend"], OpenAICompatibleClient)
    _cached = cls(
        base_url=cfg["base_url"],
        model=cfg["model"],
        api_key=cfg.get("api_key", ""),
        timeout=cfg["timeout"],
    )
    return _cached


def describe_config() -> dict:
    """Returned for debugging; never includes the api_key value."""
    cfg = _resolve_config()
    return {
        "backend": cfg["backend"],
        "base_url": cfg["base_url"],
        "model": cfg["model"],
        "api_key_set": bool(cfg.get("api_key")),
        "timeout": list(cfg["timeout"]),
    }
