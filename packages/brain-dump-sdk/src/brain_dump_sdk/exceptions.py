class BrainDumpError(Exception):
    """Base exception raised by the SDK."""


class BrainDumpConfigurationError(BrainDumpError):
    """Raised when required client configuration is missing."""


class BrainDumpAPIError(BrainDumpError):
    """Raised when Brain Dump's Supabase API rejects a request."""

    def __init__(self, message: str, *, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code
