"""Authentication manager using Device Flow OAuth (no app registration required)."""
import asyncio
import json
import logging
from typing import Optional, Dict
import httpx
import keyring

logger = logging.getLogger(__name__)


class AuthManager:
    """Manages Microsoft authentication via Device Flow (no Azure app registration needed).
    
    Uses the well-known public client ID used by Outlook, Teams, etc.
    User authenticates via a device code (like Thunderbird, New Outlook desktop).
    """

    # Microsoft's public client ID (used by official Microsoft apps)
    # No app registration required; works for any Microsoft 365 account
    PUBLIC_CLIENT_ID = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"

    KEYRING_SERVICE = "omarchy-look"
    KEYRING_ACCOUNT = "auth_cache"

    def __init__(self):
        """Initialize auth manager (no credentials needed)."""
        self.client_id = self.PUBLIC_CLIENT_ID
        self.tenant_id = "common"
        self.access_token = None
        self.refresh_token = None
        self.user_info = None

    async def login(self, device_code_callback=None) -> bool:
        """Initiate Device Flow login (user sees code on screen).

        Args:
            device_code_callback: Optional callable(user_code, verification_uri) to display device code
        
        Returns:
            True if login successful, False otherwise
        """
        try:
            await self.acquire_token_device_flow(device_code_callback)
            logger.info("Device Flow login successful")
            return True
        except Exception as e:
            logger.error(f"Device Flow login failed: {e}")
            return False

    async def acquire_token_device_flow(self, device_code_callback=None) -> dict:
        """Acquire token via Device Flow OAuth.

        User sees a code and verification URL on screen, logs in on any device,
        and the app automatically receives the token.

        Returns:
            Token response dict with 'access_token', 'refresh_token', etc.
        """
        async with httpx.AsyncClient() as client:
            # Step 1: Request device code
            device_auth_url = (
                f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/devicecode"
            )
            device_response = await client.post(
                device_auth_url,
                data={
                    "client_id": self.client_id,
                    "scope": "https://graph.microsoft.com/.default offline_access",
                },
            )
            device_response.raise_for_status()
            device_data = device_response.json()

            device_code = device_data["device_code"]
            user_code = device_data["user_code"]
            verification_uri = device_data["verification_uri"]
            expires_in = device_data["expires_in"]
            interval = device_data.get("interval", 5)

            # If callback provided, use it to display code (for QML integration)
            if device_code_callback:
                device_code_callback(user_code, verification_uri)
            else:
                # Otherwise print to terminal (for CLI/testing)
                print(f"\n{'='*70}")
                print(f"🔐 Device Login Required")
                print(f"{'='*70}")
                print(f"1. Open this URL on any device (phone, tablet, another computer):")
                print(f"   → {verification_uri}")
                print(f"2. Enter this code when prompted:")
                print(f"   → {user_code}")
                print(f"\nWaiting for authentication...")
                print(f"{'='*70}\n")

            # Step 2: Poll for token
            token_url = (
                f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
            )
            start_time = asyncio.get_event_loop().time()
            poll_count = 0

            while (asyncio.get_event_loop().time() - start_time) < expires_in:
                await asyncio.sleep(interval)
                poll_count += 1

                token_response = await client.post(
                    token_url,
                    data={
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                        "client_id": self.client_id,
                        "device_code": device_code,
                    },
                )

                if token_response.status_code == 200:
                    token_data = token_response.json()
                    self._cache_tokens(token_data)
                    self.access_token = token_data.get("access_token")
                    self.refresh_token = token_data.get("refresh_token")
                    logger.info(f"Device Flow complete (polled {poll_count} times)")
                    print("✅ Authentication successful!\n")
                    return token_data

                elif token_response.status_code == 400:
                    error = token_response.json().get("error")
                    if error == "authorization_pending":
                        # Still waiting for user to login; continue polling
                        continue
                    elif error == "expired_token":
                        raise Exception("Device code expired. Please try again.")
                    elif error == "access_denied":
                        raise Exception("Authentication denied by user.")
                    else:
                        raise Exception(f"Authentication failed: {error}")
                else:
                    raise Exception(
                        f"Unexpected response ({token_response.status_code}): "
                        f"{token_response.text}"
                    )

            raise Exception("Device code expired without user response.")

    async def get_token(self) -> Optional[str]:
        """Get a valid access token, refreshing silently if needed.

        Returns:
            Access token string, or None if unavailable
        """
        if self.access_token:
            return self.access_token

        # Try to refresh from cache
        token_data = await self.acquire_token_silent()
        if token_data:
            return token_data.get("access_token")

        logger.debug("No valid token; user must authenticate via Device Flow")
        return None

    async def acquire_token_silent(self) -> Optional[dict]:
        """Acquire token silently from cached refresh token.

        Returns:
            Token response dict or None if no cached token/refresh failed
        """
        refresh_token = self._get_cached_refresh_token()
        if not refresh_token:
            return None

        async with httpx.AsyncClient() as client:
            token_url = (
                f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
            )
            try:
                response = await client.post(
                    token_url,
                    data={
                        "grant_type": "refresh_token",
                        "client_id": self.client_id,
                        "refresh_token": refresh_token,
                        "scope": "https://graph.microsoft.com/.default offline_access",
                    },
                )

                if response.status_code == 200:
                    token_data = response.json()
                    self._cache_tokens(token_data)
                    self.access_token = token_data.get("access_token")
                    self.refresh_token = token_data.get("refresh_token")
                    logger.debug("Token refreshed silently")
                    return token_data
                else:
                    # Refresh failed; clear cached tokens
                    logger.warning(
                        f"Token refresh failed ({response.status_code}); clearing cache"
                    )
                    self._clear_cache()
                    return None

            except Exception as e:
                logger.error(f"Silent token refresh exception: {e}")
                self._clear_cache()
                return None

    def get_account(self) -> Optional[Dict[str, str]]:
        """Get cached account info (from stored tokens).

        Returns:
            Dict with 'username' or None if not authenticated
        """
        # Device Flow doesn't give us account info in the token directly
        # For now, return a placeholder
        if self.access_token:
            return {"status": "authenticated"}
        return None

    def _cache_tokens(self, token_data: dict):
        """Store tokens in OS keyring (as JSON)."""
        try:
            keyring.set_password(
                self.KEYRING_SERVICE,
                self.KEYRING_ACCOUNT,
                json.dumps({
                    "access_token": token_data.get("access_token"),
                    "refresh_token": token_data.get("refresh_token"),
                }),
            )
            logger.debug("Tokens cached in keyring")
        except Exception as e:
            logger.warning(f"Could not cache tokens in keyring: {e}")

    def _get_cached_refresh_token(self) -> Optional[str]:
        """Retrieve refresh token from keyring."""
        try:
            cached = keyring.get_password(self.KEYRING_SERVICE, self.KEYRING_ACCOUNT)
            if cached:
                data = json.loads(cached)
                return data.get("refresh_token")
        except Exception as e:
            logger.debug(f"Could not retrieve cached token: {e}")
        return None

    def _clear_cache(self):
        """Clear cached tokens from keyring."""
        try:
            keyring.delete_password(self.KEYRING_SERVICE, self.KEYRING_ACCOUNT)
            logger.debug("Tokens cleared from keyring")
        except keyring.errors.PasswordDeleteError:
            pass

    def logout(self) -> bool:
        """Clear authentication and remove tokens from cache.

        Returns:
            True if logout successful
        """
        try:
            self._clear_cache()
            self.access_token = None
            self.refresh_token = None
            self.user_info = None
            logger.info("Logout successful")
            return True
        except Exception as e:
            logger.error(f"Logout failed: {e}")
            return False

    def is_authenticated(self) -> bool:
        """Check if a valid cached token exists.

        Returns:
            True if authenticated, False otherwise
        """
        if self.access_token:
            return True
        return self._get_cached_refresh_token() is not None
