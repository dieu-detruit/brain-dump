from dataclasses import dataclass
from datetime import datetime
from typing import Literal, TypeAlias

Delegation: TypeAlias = Literal["ai", "colleague"] | None


@dataclass(frozen=True, slots=True)
class Thread:
    id: str
    title: str
    delegation: Delegation
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_response(cls, value: object) -> "Thread":
        if not isinstance(value, dict):
            raise ValueError("The API returned an invalid thread")
        delegation = value.get("delegation")
        if delegation not in (None, "ai", "colleague"):
            raise ValueError("The API returned an invalid delegation")
        return cls(
            id=str(value["id"]),
            title=str(value["title"]),
            delegation=delegation,
            created_at=_parse_datetime(value["created_at"]),
            updated_at=_parse_datetime(value["updated_at"]),
        )

    def to_dict(self) -> dict[str, str | None]:
        return {
            "id": self.id,
            "title": self.title,
            "delegation": self.delegation,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }


def _parse_datetime(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("The API returned an invalid timestamp")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
