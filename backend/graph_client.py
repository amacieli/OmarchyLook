"""Microsoft Graph API client wrapper."""
import logging
from typing import Optional, Dict, Any
import httpx

logger = logging.getLogger(__name__)


class GraphClient:
    """Async HTTP client for Microsoft Graph API with token injection and retry logic."""

    BASE_URL = "https://graph.microsoft.com/v1.0"
    RETRY_MAX = 3
    RETRY_BACKOFF = 1.0  # seconds

    def __init__(self, auth_manager: Any):
        """Initialize Graph client.

        Args:
            auth_manager: AuthManager instance for token injection
        """
        self.auth_manager = auth_manager
        self.client = httpx.AsyncClient(timeout=30.0)

    async def _inject_token(self) -> Optional[str]:
        """Get and inject authorization token into headers.

        Returns:
            Bearer token or None if unavailable
        """
        token = self.auth_manager.get_token()
        if not token:
            logger.error("Failed to obtain access token")
            return None
        return token

    async def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """GET request to Graph API.

        Args:
            path: Relative path (e.g., "/me/messages")
            params: Query parameters

        Returns:
            Response JSON dict, or None on error
        """
        token = await self._inject_token()
        if not token:
            return None

        url = f"{self.BASE_URL}{path}"
        headers = {"Authorization": f"Bearer {token}"}

        try:
            response = await self.client.get(url, params=params, headers=headers)

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                logger.warning(f"Throttled (429). Retry-After: {retry_after}s")
                return None

            if response.status_code == 401:
                logger.error("Unauthorized (401). Token may have expired.")
                return None

            response.raise_for_status()
            return response.json()

        except httpx.HTTPError as e:
            logger.error(f"GET {path} failed: {e}")
            return None

    async def post(self, path: str, body: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        """POST request to Graph API.

        Args:
            path: Relative path
            body: Request body as dict

        Returns:
            Response JSON dict, or None on error
        """
        token = await self._inject_token()
        if not token:
            return None

        url = f"{self.BASE_URL}{path}"
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

        try:
            response = await self.client.post(url, json=body or {}, headers=headers)

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                logger.warning(f"Throttled (429). Retry-After: {retry_after}s")
                return None

            if response.status_code == 401:
                logger.error("Unauthorized (401). Token may have expired.")
                return None

            response.raise_for_status()
            return response.json()

        except httpx.HTTPError as e:
            logger.error(f"POST {path} failed: {e}")
            return None

    async def patch(self, path: str, body: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """PATCH request to Graph API.

        Args:
            path: Relative path
            body: Request body as dict

        Returns:
            Response JSON dict, or None on error
        """
        token = await self._inject_token()
        if not token:
            return None

        url = f"{self.BASE_URL}{path}"
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

        try:
            response = await self.client.patch(url, json=body, headers=headers)

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                logger.warning(f"Throttled (429). Retry-After: {retry_after}s")
                return None

            if response.status_code == 401:
                logger.error("Unauthorized (401). Token may have expired.")
                return None

            response.raise_for_status()
            return response.json()

        except httpx.HTTPError as e:
            logger.error(f"PATCH {path} failed: {e}")
            return None

    async def delete(self, path: str) -> bool:
        """DELETE request to Graph API.

        Args:
            path: Relative path

        Returns:
            True if successful, False otherwise
        """
        token = await self._inject_token()
        if not token:
            return False

        url = f"{self.BASE_URL}{path}"
        headers = {"Authorization": f"Bearer {token}"}

        try:
            response = await self.client.delete(url, headers=headers)

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                logger.warning(f"Throttled (429). Retry-After: {retry_after}s")
                return False

            if response.status_code == 401:
                logger.error("Unauthorized (401). Token may have expired.")
                return False

            response.raise_for_status()
            return True

        except httpx.HTTPError as e:
            logger.error(f"DELETE {path} failed: {e}")
            return False

    async def paginate(
        self, path: str, params: Optional[Dict[str, Any]] = None
    ) -> list:
        """Paginate through Graph API results following @odata.nextLink.

        Args:
            path: Initial relative path
            params: Query parameters

        Returns:
            List of all items across pages
        """
        all_items = []
        next_link = None

        while True:
            if next_link:
                # nextLink is a full URL, not relative
                url = next_link
                token = await self._inject_token()
                if not token:
                    break

                headers = {"Authorization": f"Bearer {token}"}
                try:
                    response = await self.client.get(url, headers=headers)
                    response.raise_for_status()
                    data = response.json()
                except httpx.HTTPError as e:
                    logger.error(f"Pagination failed: {e}")
                    break
            else:
                data = await self.get(path, params)
                if not data:
                    break

            items = data.get("value", [])
            all_items.extend(items)

            next_link = data.get("@odata.nextLink")
            if not next_link:
                break

        return all_items

    async def close(self):
        """Close the async HTTP client."""
        await self.client.aclose()
