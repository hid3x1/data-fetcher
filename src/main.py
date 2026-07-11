"""Fetch posts from a public API with retries, structured logging, and typed settings."""

from __future__ import annotations

import httpx
from loguru import logger
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)


class Settings(BaseSettings):
    """Runtime configuration, overridable via DATA_FETCHER_* environment variables."""

    model_config = SettingsConfigDict(env_prefix="DATA_FETCHER_")

    base_url: str = "https://jsonplaceholder.typicode.com"
    timeout_seconds: float = 10.0
    fetch_limit: int = Field(default=5, gt=0)


class Post(BaseModel):
    """A single post as returned by the /posts endpoint."""

    id: int
    user_id: int = Field(alias="userId")
    title: str
    body: str


@retry(
    retry=retry_if_exception_type(httpx.HTTPError),
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    reraise=True,
)
def _request_posts(client: httpx.Client, settings: Settings) -> httpx.Response:
    logger.debug(f"GET {settings.base_url}/posts")
    response = client.get("/posts", params={"_limit": settings.fetch_limit})
    response.raise_for_status()
    return response


def fetch_posts(settings: Settings) -> list[Post]:
    """Fetch posts from the configured API, retrying on transient HTTP errors."""
    with httpx.Client(
        base_url=settings.base_url, timeout=settings.timeout_seconds
    ) as client:
        response = _request_posts(client, settings)
    return [Post.model_validate(item) for item in response.json()]


def main() -> None:
    """Fetch and log a batch of posts."""
    settings = Settings()
    logger.info(f"Fetching up to {settings.fetch_limit} posts from {settings.base_url}")
    try:
        posts = fetch_posts(settings)
    except httpx.HTTPError:
        logger.exception("Failed to fetch posts after retries")
        raise
    logger.success(f"Fetched {len(posts)} posts")
    for post in posts:
        logger.info(f"[{post.id}] {post.title}")


if __name__ == "__main__":
    main()
