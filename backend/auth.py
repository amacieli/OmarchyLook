"""Authentication manager using MSAL for Microsoft Graph."""
import os
import json
import logging
from typing import Optional, Dict, Any
from msal import PublicClientApplication
import keyring

logger = logging.getLogger(__name__)


class AuthManager:
    """Manages Microsoft authentication via MSAL with keyring caching."""

    KEYRING_SERVICE = "omarchy-look"
    KEYRING_ACCOUNT = "auth_cache"

    def __init__(self, client_id: str, tenant_id: str):
        """Initialize auth manager.

        Args:
            client_id: Azure app registration client ID
            tenant_id: Azure tenant ID
        """
        self.client_id = client_id
        self.tenant_id = tenant_id
        self.authority = f"https://login.microsoftonline.com/{tenant_id}"

        # Scopes for Mail, Calendar, Contacts, Tasks, User profile, offline access
        self.scopes = [
            "User.Read",
            "Mail.ReadWrite",
            "Mail.Send",
            "Calendars.ReadWrite",
            "Contacts.ReadWrite",
            "Tasks.ReadWrite",
            "offline_access",
        ]

        self.app = PublicClientApplication(
            client_id=self.client_id,
            authority=self.authority,
            token_cache=self._get_token_cache(),
        )

    def _get_token_cache(self) -> Any:
        """Create a token cache backed by OS keyring.

        Returns:
            MSAL SerializableTokenCache connected to keyring
        """
        from msal import SerializableTokenCache

        cache = SerializableTokenCache()

        # Try to load cached tokens from keyring
        cached_data = keyring.get_password(self.KEYRING_SERVICE, self.KEYRING_ACCOUNT)
        if cached_data:
            try:
                cache.deserialize(cached_data)
                logger.debug("Loaded auth tokens from keyring")
            except Exception as e:
                logger.warning(f"Failed to load cached tokens: {e}")

        # Set up cache save hook
        def save_to_keyring():
            try:
                keyring.set_password(
                    self.KEYRING_SERVICE,
                    self.KEYRING_ACCOUNT,
                    cache.serialize(),
                )
                logger.debug("Saved auth tokens to keyring")
            except Exception as e:
                logger.error(f"Failed to save tokens to keyring: {e}")

        cache.add_tokens_changed_listener(save_to_keyring)
        return cache

    def login(self) -> bool:
        """Initiate interactive login via system browser.

        Uses loopback redirect (http://localhost) to capture auth code.

        Returns:
            True if login successful, False otherwise
        """
        try:
            # Acquire token interactively using system browser
            result = self.app.acquire_token_interactive(
                scopes=self.scopes,
                redirect_uri="http://localhost",
            )

            if "access_token" in result:
                logger.info(f"Login successful: {result.get('id_token_claims', {}).get('name', 'Unknown')}")
                return True
            else:
                error_desc = result.get("error_description", result.get("error", "Unknown error"))
                logger.error(f"Login failed: {error_desc}")
                return False

        except Exception as e:
            logger.error(f"Interactive login exception: {e}")
            return False

    def get_token(self) -> Optional[str]:
        """Get a valid access token, refreshing silently if needed.

        Returns:
            Access token string, or None if unavailable
        """
        try:
            # First, try silent refresh with cached tokens
            accounts = self.app.get_accounts()
            if accounts:
                result = self.app.acquire_token_silent(
                    scopes=self.scopes,
                    account=accounts[0],
                )

                if "access_token" in result:
                    logger.debug("Token acquired silently")
                    return result["access_token"]
                else:
                    error_desc = result.get("error_description", result.get("error", "Unknown error"))
                    logger.warning(f"Silent token refresh failed: {error_desc}")
                    return None
            else:
                logger.debug("No cached accounts; user must login interactively")
                return None

        except Exception as e:
            logger.error(f"Token acquisition exception: {e}")
            return None

    def get_account(self) -> Optional[Dict[str, str]]:
        """Get the current authenticated account info.

        Returns:
            Dict with 'username', 'name', 'tenant_id', or None if not authenticated
        """
        try:
            accounts = self.app.get_accounts()
            if not accounts:
                return None

            account = accounts[0]
            return {
                "username": account.get("username", ""),
                "name": account.get("name", account.get("username", "")),
                "tenant_id": account.get("home_account_id", "").split(".")[1] if "." in account.get("home_account_id", "") else self.tenant_id,
            }
        except Exception as e:
            logger.error(f"Failed to get account info: {e}")
            return None

    def logout(self) -> bool:
        """Clear authentication and remove tokens from cache.

        Returns:
            True if logout successful
        """
        try:
            accounts = self.app.get_accounts()
            if accounts:
                self.app.remove_account(accounts[0])

            # Clear keyring
            try:
                keyring.delete_password(self.KEYRING_SERVICE, self.KEYRING_ACCOUNT)
            except keyring.errors.PasswordDeleteError:
                pass  # Key didn't exist

            logger.info("Logout successful")
            return True
        except Exception as e:
            logger.error(f"Logout failed: {e}")
            return False

    def is_authenticated(self) -> bool:
        """Check if a valid cached account exists.

        Returns:
            True if authenticated, False otherwise
        """
        try:
            accounts = self.app.get_accounts()
            return len(accounts) > 0
        except Exception as e:
            logger.error(f"Auth check failed: {e}")
            return False
