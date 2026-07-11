import httpx
import pytest
import respx
from hypothesis import given
from hypothesis import strategies as st
from tenacity import wait_none

import main


@pytest.fixture(autouse=True)
def _no_retry_wait():
    original_wait = main._request_posts.retry.wait
    main._request_posts.retry.wait = wait_none()
    yield
    main._request_posts.retry.wait = original_wait


class TestSettings:
    def test_defaults(self):
        settings = main.Settings()

        assert settings.base_url == "https://jsonplaceholder.typicode.com"
        assert settings.timeout_seconds == 10.0
        assert settings.fetch_limit == 5

    def test_env_overrides(self, monkeypatch):
        monkeypatch.setenv("DATA_FETCHER_BASE_URL", "https://example.com")
        monkeypatch.setenv("DATA_FETCHER_FETCH_LIMIT", "2")

        settings = main.Settings()

        assert settings.base_url == "https://example.com"
        assert settings.fetch_limit == 2

    def test_fetch_limit_must_be_positive(self):
        with pytest.raises(ValueError, match="fetch_limit"):
            main.Settings(fetch_limit=0)

    @given(fetch_limit=st.integers(min_value=1, max_value=1_000_000))
    def test_fetch_limit_accepts_any_positive_int(self, fetch_limit):
        settings = main.Settings(fetch_limit=fetch_limit)

        assert settings.fetch_limit == fetch_limit

    @given(fetch_limit=st.integers(max_value=0))
    def test_fetch_limit_rejects_any_non_positive_int(self, fetch_limit):
        with pytest.raises(ValueError, match="fetch_limit"):
            main.Settings(fetch_limit=fetch_limit)


class TestPost:
    def test_parses_camel_case_user_id(self):
        post = main.Post.model_validate(
            {"id": 1, "userId": 2, "title": "t", "body": "b"}
        )

        assert post.user_id == 2

    @given(
        post_id=st.integers(),
        user_id=st.integers(),
        title=st.text(),
        body=st.text(),
    )
    def test_round_trips_arbitrary_fields(self, post_id, user_id, title, body):
        post = main.Post.model_validate(
            {"id": post_id, "userId": user_id, "title": title, "body": body}
        )

        assert post.id == post_id
        assert post.user_id == user_id
        assert post.title == title
        assert post.body == body


class TestFetchPosts:
    @respx.mock
    def test_returns_parsed_posts_on_success(self):
        settings = main.Settings(base_url="https://api.test")
        route = respx.get("https://api.test/posts").mock(
            return_value=httpx.Response(
                200,
                json=[
                    {"id": 1, "userId": 1, "title": "a", "body": "b"},
                    {"id": 2, "userId": 1, "title": "c", "body": "d"},
                ],
            )
        )

        posts = main.fetch_posts(settings)

        assert route.called
        assert [p.id for p in posts] == [1, 2]

    @respx.mock
    def test_recovers_after_transient_error(self):
        settings = main.Settings(base_url="https://api.test")
        route = respx.get("https://api.test/posts").mock(
            side_effect=[
                httpx.Response(500),
                httpx.Response(
                    200, json=[{"id": 1, "userId": 1, "title": "a", "body": "b"}]
                ),
            ]
        )

        posts = main.fetch_posts(settings)

        assert route.call_count == 2
        assert len(posts) == 1

    @respx.mock
    def test_gives_up_after_max_attempts(self):
        settings = main.Settings(base_url="https://api.test")
        route = respx.get("https://api.test/posts").mock(
            return_value=httpx.Response(500)
        )

        with pytest.raises(httpx.HTTPStatusError):
            main.fetch_posts(settings)

        assert route.call_count == 3

    @respx.mock
    def test_sends_fetch_limit_as_query_param(self):
        settings = main.Settings(base_url="https://api.test", fetch_limit=3)
        route = respx.get("https://api.test/posts", params={"_limit": "3"}).mock(
            return_value=httpx.Response(200, json=[])
        )

        main.fetch_posts(settings)

        assert route.called

    @respx.mock
    def test_passes_configured_timeout_to_client(self, mocker):
        settings = main.Settings(base_url="https://api.test", timeout_seconds=3.5)
        spy = mocker.spy(main.httpx, "Client")
        respx.get("https://api.test/posts").mock(
            return_value=httpx.Response(200, json=[])
        )

        main.fetch_posts(settings)

        spy.assert_called_once_with(base_url="https://api.test", timeout=3.5)


class TestMain:
    def test_reraises_after_failed_fetch(self, mocker):
        mock_logger = mocker.patch.object(main, "logger")
        mocker.patch.object(main, "fetch_posts", side_effect=httpx.HTTPError("boom"))

        with pytest.raises(httpx.HTTPError):
            main.main()

        mock_logger.exception.assert_called_once_with(
            "Failed to fetch posts after retries"
        )

    def test_calls_fetch_posts_on_success(self, mocker):
        mock_logger = mocker.patch.object(main, "logger")
        settings = main.Settings()
        mocker.patch.object(main, "Settings", return_value=settings)
        post = main.Post.model_validate(
            {"id": 1, "userId": 1, "title": "t", "body": "b"}
        )
        fetch_posts = mocker.patch.object(main, "fetch_posts", return_value=[post])

        main.main()

        fetch_posts.assert_called_once_with(settings)
        mock_logger.info.assert_any_call(
            f"Fetching up to {settings.fetch_limit} posts from {settings.base_url}"
        )
        mock_logger.success.assert_called_once_with("Fetched 1 posts")
        mock_logger.info.assert_any_call(f"[{post.id}] {post.title}")
