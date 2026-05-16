"""Data models for HermesViz."""

from dataclasses import dataclass, field
from typing import Optional
from datetime import datetime


@dataclass
class SessionSummary:
    session_key: str
    session_id: str
    created_at: str
    updated_at: str
    display_name: Optional[str]
    platform: str
    chat_type: str
    input_tokens: int
    output_tokens: int
    cache_read_tokens: int
    cache_write_tokens: int
    total_tokens: int
    last_prompt_tokens: int
    estimated_cost_usd: float
    cost_status: str
    model: str = ""
    base_url: str = ""

    @property
    def created_datetime(self) -> Optional[datetime]:
        try:
            return datetime.fromisoformat(self.created_at)
        except (ValueError, TypeError):
            return None


@dataclass
class SessionDetail:
    session_id: str
    model: str
    base_url: str
    platform: str
    session_start: str
    last_updated: str
    system_prompt: str = ""
    tools_count: int = 0
    messages_count: int = 0
    total_tokens: int = 0
    estimated_cost_usd: float = 0.0


@dataclass
class GatewayStatus:
    pid: int
    state: str
    active_agents: int
    platforms: dict = field(default_factory=dict)
    updated_at: str = ""


@dataclass
class OverviewStats:
    total_sessions: int = 0
    total_tokens: int = 0
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cost_usd: float = 0.0
    active_sessions_24h: int = 0
    gateway_running: bool = False
    models_used: list = field(default_factory=list)
    platforms_used: list = field(default_factory=list)


@dataclass
class DailyStats:
    date: str
    sessions: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    total_tokens: int = 0
    cost_usd: float = 0.0


@dataclass
class CronJob:
    name: str
    schedule: str
    enabled: bool
    last_run: Optional[str] = None
    next_run: Optional[str] = None
    status: str = "unknown"


@dataclass
class Skill:
    name: str
    description: str
    path: str
    size_bytes: int = 0
