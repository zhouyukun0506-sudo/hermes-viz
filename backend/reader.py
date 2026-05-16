"""Read Hermes data from local files and optional API."""

import json
import os
import yaml
import sqlite3
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Optional

from .models import (
    SessionSummary, SessionDetail, GatewayStatus,
    OverviewStats, DailyStats, CronJob, Skill
)

HERMES_HOME = Path(os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes")))
SESSIONS_DIR = HERMES_HOME / "sessions"
GATEWAY_STATE_FILE = HERMES_HOME / "gateway_state.json"
CONFIG_FILE = HERMES_HOME / "config.yaml"
STATE_DB = HERMES_HOME / "state.db"
SKILLS_DIR = HERMES_HOME / "skills"
CRON_DIR = HERMES_HOME / "cron"
LOGS_DIR = HERMES_HOME / "logs"


def read_sessions() -> list[SessionSummary]:
    """Read all sessions from the index and individual files."""
    sessions = []
    index_path = SESSIONS_DIR / "sessions.json"

    if not index_path.exists():
        return sessions

    try:
        with open(index_path, "r") as f:
            index: dict = json.load(f)
    except (json.JSONDecodeError, IOError):
        return sessions

    # Enrich with model info from individual session files
    for key, data in index.items():
        sess = SessionSummary(
            session_key=data.get("session_key", key),
            session_id=data.get("session_id", ""),
            created_at=data.get("created_at", ""),
            updated_at=data.get("updated_at", ""),
            display_name=data.get("display_name"),
            platform=data.get("platform", "unknown"),
            chat_type=data.get("chat_type", "unknown"),
            input_tokens=data.get("input_tokens", 0),
            output_tokens=data.get("output_tokens", 0),
            cache_read_tokens=data.get("cache_read_tokens", 0),
            cache_write_tokens=data.get("cache_write_tokens", 0),
            total_tokens=data.get("total_tokens", 0),
            last_prompt_tokens=data.get("last_prompt_tokens", 0),
            estimated_cost_usd=data.get("estimated_cost_usd", 0.0),
            cost_status=data.get("cost_status", "unknown"),
        )
        # Try to get model from individual session file
        session_file = SESSIONS_DIR / f"session_{sess.session_id}.json"
        if session_file.exists():
            try:
                with open(session_file, "r") as f:
                    sess_data = json.load(f)
                sess.model = sess_data.get("model", "")
                sess.base_url = sess_data.get("base_url", "")
            except (json.JSONDecodeError, IOError, OSError):
                pass

        sessions.append(sess)

    # Sort by created_at descending
    sessions.sort(key=lambda s: s.created_at, reverse=True)
    return sessions


def read_session_detail(session_id: str) -> Optional[SessionDetail]:
    """Read detailed info for a single session."""
    # Try multiple filename patterns
    candidates = [
        SESSIONS_DIR / f"session_{session_id}.json",
        SESSIONS_DIR / f"{session_id}.json",
        SESSIONS_DIR / f"{session_id}.jsonl",
    ]
    session_file = None
    for c in candidates:
        if c.exists():
            session_file = c
            break

    if session_file is None:
        return None

    try:
        if str(session_file).endswith(".jsonl"):
            # JSONL format: count messages
            messages_count = 0
            with open(session_file, "r") as f:
                for _ in f:
                    messages_count += 1
            return SessionDetail(
                session_id=session_id,
                model="",
                base_url="",
                platform="",
                session_start="",
                last_updated="",
                messages_count=messages_count,
            )

        with open(session_file, "r") as f:
            data = json.load(f)

        tools = data.get("tools", [])
        messages = data.get("messages", data.get("transcript", []))
        if isinstance(messages, list):
            messages_count = len(messages)
        else:
            messages_count = 0

        return SessionDetail(
            session_id=data.get("session_id", session_id),
            model=data.get("model", ""),
            base_url=data.get("base_url", ""),
            platform=data.get("platform", ""),
            session_start=data.get("session_start", ""),
            last_updated=data.get("last_updated", ""),
            system_prompt=data.get("system_prompt", ""),
            tools_count=len(tools) if isinstance(tools, list) else 0,
            messages_count=messages_count,
            total_tokens=data.get("total_tokens", 0),
            estimated_cost_usd=data.get("estimated_cost_usd", 0.0),
        )
    except (json.JSONDecodeError, IOError, OSError):
        return None


def read_gateway_status() -> Optional[GatewayStatus]:
    """Read the current gateway/agent status."""
    if not GATEWAY_STATE_FILE.exists():
        return None

    try:
        with open(GATEWAY_STATE_FILE, "r") as f:
            data = json.load(f)

        return GatewayStatus(
            pid=data.get("pid", 0),
            state=data.get("gateway_state", "unknown"),
            active_agents=data.get("active_agents", 0),
            platforms=data.get("platforms", {}),
            updated_at=data.get("updated_at", ""),
        )
    except (json.JSONDecodeError, IOError):
        return None


def read_overview() -> OverviewStats:
    """Compute overview statistics from all sessions."""
    sessions = read_sessions()
    gateway = read_gateway_status()

    stats = OverviewStats()
    stats.total_sessions = len(sessions)
    stats.gateway_running = gateway is not None and gateway.state == "running"
    models_set = set()
    platforms_set = set()

    now = datetime.now(timezone.utc)
    cutoff_24h = now - timedelta(hours=24)

    for s in sessions:
        stats.total_input_tokens += s.input_tokens
        stats.total_output_tokens += s.output_tokens
        stats.total_tokens += s.total_tokens
        stats.total_cost_usd += s.estimated_cost_usd

        if s.model:
            models_set.add(s.model)
        platforms_set.add(s.platform)

        if s.created_datetime and s.created_datetime > cutoff_24h:
            stats.active_sessions_24h += 1

    stats.models_used = sorted(models_set)
    stats.platforms_used = sorted(platforms_set)

    return stats


def read_daily_stats() -> list[DailyStats]:
    """Compute daily aggregated token/cost stats."""
    sessions = read_sessions()
    daily: dict[str, DailyStats] = {}

    for s in sessions:
        try:
            dt = datetime.fromisoformat(s.created_at)
            date_key = dt.strftime("%Y-%m-%d")
        except (ValueError, TypeError):
            continue

        if date_key not in daily:
            daily[date_key] = DailyStats(date=date_key)
        ds = daily[date_key]
        ds.sessions += 1
        ds.input_tokens += s.input_tokens
        ds.output_tokens += s.output_tokens
        ds.total_tokens += s.total_tokens
        ds.cost_usd += s.estimated_cost_usd

    return sorted(daily.values(), key=lambda d: d.date)


def read_config() -> dict:
    """Read Hermes config.yaml."""
    if not CONFIG_FILE.exists():
        return {}
    try:
        with open(CONFIG_FILE, "r") as f:
            return yaml.safe_load(f) or {}
    except (yaml.YAMLError, IOError):
        return {}


def read_skills() -> list[Skill]:
    """List installed skills."""
    skills = []
    if not SKILLS_DIR.exists():
        return skills

    for item in sorted(SKILLS_DIR.iterdir()):
        if item.is_dir():
            skill_md = item / "SKILL.md"
            if skill_md.exists():
                try:
                    desc = skill_md.read_text()[:200].split("\n")[0].strip("# ")[:100]
                except IOError:
                    desc = ""
                skills.append(Skill(
                    name=item.name,
                    description=desc,
                    path=str(item),
                    size_bytes=sum(f.stat().st_size for f in item.rglob("*") if f.is_file()),
                ))
    return skills


def read_cron_jobs() -> list[CronJob]:
    """List cron jobs from the cron directory."""
    jobs = []
    if not CRON_DIR.exists():
        return jobs

    for item in sorted(CRON_DIR.iterdir()):
        if item.suffix in (".yaml", ".yml", ".json"):
            jobs.append(CronJob(
                name=item.stem,
                schedule="",
                enabled=True,
                status="configured",
            ))

    # Also check for crontab-style config
    crontab_file = HERMES_HOME / "crontab.json"
    if crontab_file.exists():
        try:
            with open(crontab_file, "r") as f:
                crontab = json.load(f)
            for entry in crontab if isinstance(crontab, list) else []:
                jobs.append(CronJob(
                    name=entry.get("name", entry.get("id", "unknown")),
                    schedule=entry.get("schedule", entry.get("cron", "")),
                    enabled=entry.get("enabled", True),
                    last_run=entry.get("last_run"),
                    next_run=entry.get("next_run"),
                    status=entry.get("status", "unknown"),
                ))
        except (json.JSONDecodeError, IOError):
            pass

    return jobs


def read_state_from_db() -> dict:
    """Try to read additional stats from SQLite state.db."""
    result = {"error": None, "sessions_count": 0, "memories_count": 0}

    if not STATE_DB.exists():
        result["error"] = "state.db not found"
        return result

    try:
        conn = sqlite3.connect(str(STATE_DB))
        cursor = conn.cursor()

        # Count tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        for table in tables:
            try:
                cursor.execute(f"SELECT COUNT(*) FROM [{table}]")
                count = cursor.fetchone()[0]
                result[f"table_{table}"] = count
            except sqlite3.Error:
                pass

        conn.close()
    except sqlite3.Error as e:
        result["error"] = str(e)

    return result
