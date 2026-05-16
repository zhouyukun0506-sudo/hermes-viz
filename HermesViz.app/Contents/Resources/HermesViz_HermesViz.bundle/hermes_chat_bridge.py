#!/usr/bin/env python3
"""
Hermes Chat Bridge — JSON-lines streaming protocol for HermesViz.

Bridges the Hermes AIAgent's callback-based streaming API to a simple
JSON-lines protocol over stdout/stdin, allowing the Swift app to consume
streaming tokens, thinking status, reasoning text, and tool call events
in real-time.

Protocol (stdout, one JSON object per line):
    {"type":"thinking","text":"🤔 Analyzing..."}
    {"type":"reasoning","text":"Let me consider..."}
    {"type":"delta","text":"Hello"}
    {"type":"tool_start","name":"bash","id":"tc_123","input":"ls -la"}
    {"type":"tool_end","name":"bash","success":true,"output":"..."}
    {"type":"done","content":"Full response text"}
    {"type":"error","message":"..."}

Protocol (stdin):
    {"type":"abort"}  — interrupt the current generation

Usage:
    python3 hermes_chat_bridge.py [--resume SESSION_ID] "prompt text"
"""

from __future__ import annotations

import json
import logging
import os
import select
import signal
import sys
import threading
from pathlib import Path
from typing import Optional

# Ensure hermes-agent is importable
HERMES_AGENT_DIR = Path(os.environ.get(
    "HERMES_AGENT_DIR",
    os.path.expanduser("~/.hermes/hermes-agent")
)).resolve()

if str(HERMES_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(HERMES_AGENT_DIR))

# Suppress all logging to stderr — we only communicate via stdout JSON-lines
logging.disable(logging.CRITICAL)

# ── Abort mechanism ──────────────────────────────────────────────────────
_abort_requested = threading.Event()


def _emit(event: dict) -> None:
    """Write a JSON-lines event to stdout (thread-safe via line buffering)."""
    try:
        line = json.dumps(event, ensure_ascii=False)
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        pass


def _stdin_watcher(on_chat: Optional[callable] = None) -> None:
    """Background thread: watch stdin for commands."""
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                cmd = json.loads(line)
                ctype = cmd.get("type")
                if ctype == "abort":
                    _abort_requested.set()
                elif ctype == "chat" and on_chat:
                    prompt = cmd.get("prompt", "")
                    on_chat(prompt)
            except (json.JSONDecodeError, TypeError):
                pass
    except (EOFError, OSError, ValueError):
        pass


# ── Callbacks ────────────────────────────────────────────────────────────

def _on_thinking(text: str) -> None:
    """Called when the agent's thinking status changes."""
    _emit({"type": "thinking", "text": text})


def _on_reasoning(text: str) -> None:
    """Called with reasoning/thinking token deltas."""
    if text:
        _emit({"type": "reasoning", "text": text})


def _on_stream_delta(text) -> None:
    """Called with each content token as it's generated."""
    if _abort_requested.is_set():
        raise KeyboardInterrupt("User requested abort")
    if text:
        _emit({"type": "delta", "text": str(text)})


def _on_tool_start(tool_call_id: str, function_name: str, function_args: dict) -> None:
    """Called when a tool call begins."""
    args_preview = ""
    if function_args:
        try:
            args_preview = json.dumps(function_args, ensure_ascii=False)[:200]
        except (TypeError, ValueError):
            args_preview = str(function_args)[:200]
    _emit({
        "type": "tool_start",
        "id": tool_call_id,
        "name": function_name,
        "input": args_preview,
    })


def _on_tool_complete(tool_call_id: str, function_name: str, result: dict) -> None:
    """Called when a tool call finishes."""
    success = True
    output = ""
    if isinstance(result, dict):
        success = result.get("success", True)
        output = result.get("output", result.get("diff", ""))
        if isinstance(output, str):
            output = output[:500]
    _emit({
        "type": "tool_end",
        "id": tool_call_id,
        "name": function_name,
        "success": success,
        "output": str(output)[:500],
    })


def _on_tool_progress(tool_name: str, args_preview: str) -> None:
    """Called with tool execution progress."""
    _emit({"type": "tool_progress", "name": tool_name, "preview": args_preview[:200]})


# ── Main ─────────────────────────────────────────────────────────────────

def _init_agent(resume_session_id: Optional[str] = None):
    """Initialize and return an AIAgent instance."""
    from hermes_cli.config import load_config
    config = load_config()

    # Resolve model/provider
    model_config = config.get("model", {})
    model = model_config.get("default", model_config.get("model", ""))
    provider = model_config.get("provider", "auto")
    base_url = model_config.get("base_url", "")
    api_key = model_config.get("api_key", "")

    model = os.environ.get("HERMES_INFERENCE_MODEL", model)
    provider = os.environ.get("HERMES_INFERENCE_PROVIDER", provider)

    if not model:
        raise ValueError("No model configured. Run 'hermes model' to set up.")

    from hermes_cli.runtime_provider import resolve_runtime_provider
    runtime = resolve_runtime_provider(
        requested=provider,
        target_model=model,
        explicit_base_url=base_url,
        explicit_api_key=api_key,
    )

    effective_model = runtime.get("model", model)
    effective_base_url = runtime.get("base_url", base_url)
    effective_api_key = runtime.get("api_key", api_key)
    effective_provider = runtime.get("provider", provider)
    api_mode = runtime.get("api_mode", "")

    try:
        from hermes_cli.tools_config import _get_platform_tools
        enabled_toolsets = list(_get_platform_tools(config, "cli"))
    except Exception:
        enabled_toolsets = None

    from run_agent import AIAgent
    agent = AIAgent(
        base_url=effective_base_url,
        api_key=effective_api_key,
        provider=effective_provider,
        api_mode=api_mode or None,
        model=effective_model,
        max_iterations=90,
        enabled_toolsets=enabled_toolsets,
        quiet_mode=True,
        platform="hermesviz",
        session_id=resume_session_id,
        thinking_callback=_on_thinking,
        reasoning_callback=_on_reasoning,
        stream_delta_callback=_on_stream_delta,
        tool_start_callback=_on_tool_start,
        tool_complete_callback=_on_tool_complete,
        tool_progress_callback=_on_tool_progress,
    )

    history = []
    if resume_session_id:
        try:
            sessions_dir = os.path.expanduser("~/.hermes/sessions")
            session_file = os.path.join(sessions_dir, f"session_{resume_session_id}.json")
            if os.path.exists(session_file):
                with open(session_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    history = data.get("messages", [])
        except Exception as e:
            _emit({"type": "error", "message": f"Context load failed: {e}"})

    return agent, history

def run_bridge_server(resume_session_id: Optional[str] = None) -> int:
    """Persistent server mode: one agent, multiple chat turns."""
    _emit({"type": "thinking", "text": "🔄 Initializing..."})
    try:
        agent, conversation_history = _init_agent(resume_session_id)
    except Exception as e:
        _emit({"type": "error", "message": str(e)})
        return 1

    _emit({"type": "session_id", "id": agent.session_id})

    def on_chat_request(prompt: str):
        nonlocal conversation_history
        _abort_requested.clear()
        
        # Guard stderr
        devnull = open(os.devnull, "w", encoding="utf-8")
        old_stderr = sys.stderr
        sys.stderr = devnull
        
        try:
            result = agent.run_conversation(prompt, conversation_history=conversation_history)
            conversation_history = result["messages"]
            response = result["final_response"]
            
            # Emit usage
            _emit({
                "type": "usage",
                "prompt_tokens": result.get("input_tokens", 0),
                "completion_tokens": result.get("output_tokens", 0)
            })
            
            # Emit done
            final_text = ""
            if response:
                if isinstance(response, str): final_text = response
                elif hasattr(response, "content"):
                    if isinstance(response.content, str): final_text = response.content
                    elif isinstance(response.content, list):
                        final_text = "\n".join([b.text for b in response.content if hasattr(b, "text")])
                else: final_text = str(response)
            _emit({"type": "done", "content": final_text})
            
        except KeyboardInterrupt:
            _emit({"type": "aborted", "content": ""})
        except Exception as e:
            _emit({"type": "error", "message": str(e)})
        finally:
            sys.stderr = old_stderr
            devnull.close()

    # The watcher will now call on_chat_request
    _stdin_watcher(on_chat=on_chat_request)
    return 0


def run_bridge(prompt: str, resume_session_id: Optional[str] = None) -> int:
    """Run the agent with streaming callbacks and JSON-lines output."""

    # Start stdin watcher thread
    watcher = threading.Thread(target=_stdin_watcher, daemon=True)
    watcher.start()

    # Auto-approve tool calls (non-interactive)
    os.environ["HERMES_YOLO_MODE"] = "1"
    os.environ["HERMES_ACCEPT_HOOKS"] = "1"

    try:
        _emit({"type": "thinking", "text": "🔄 Initializing..."})
        agent, conversation_history = _init_agent(resume_session_id)
        _emit({"type": "session_id", "id": agent.session_id})

        # Redirect stderr to devnull during execution
        devnull = open(os.devnull, "w", encoding="utf-8")
        old_stderr = sys.stderr
        sys.stderr = devnull

        try:
            result = agent.run_conversation(prompt, conversation_history=conversation_history)
            response = result["final_response"]
        except KeyboardInterrupt:
            _emit({"type": "aborted", "content": ""})
            return 0
        finally:
            sys.stderr = old_stderr
            try:
                devnull.close()
            except Exception:
                pass

        # Emit usage info
        try:
            _emit({
                "type": "usage",
                "prompt_tokens": result.get("input_tokens", 0),
                "completion_tokens": result.get("output_tokens", 0)
            })
        except Exception:
            pass

        # Extract final text
        final_text = ""
        if response:
            if isinstance(response, str):
                final_text = response
            elif isinstance(response, dict):
                final_text = response.get("content", response.get("text", str(response)))
            elif hasattr(response, "content"):
                content = response.content
                if isinstance(content, list):
                    parts = []
                    for block in content:
                        if hasattr(block, "text"):
                            parts.append(block.text)
                        elif isinstance(block, dict) and "text" in block:
                            parts.append(block["text"])
                    final_text = "\n".join(parts)
                elif isinstance(content, str):
                    final_text = content
            else:
                final_text = str(response)

        _emit({"type": "done", "content": final_text})
        return 0

    except KeyboardInterrupt:
        _emit({"type": "aborted", "content": ""})
        return 0
    except Exception as e:
        _emit({"type": "error", "message": str(e)})
        return 1


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Hermes Chat Bridge")
    parser.add_argument("prompt", nargs="?", default=None, help="User prompt to send")
    parser.add_argument("--resume", default=None, help="Session ID to resume")
    parser.add_argument("--server", action="store_true", help="Start in persistent server mode")
    args = parser.parse_args()

    # Auto-approve tool calls (non-interactive)
    os.environ["HERMES_YOLO_MODE"] = "1"
    os.environ["HERMES_ACCEPT_HOOKS"] = "1"

    if args.server:
        sys.exit(run_bridge_server(args.resume))
    elif args.prompt:
        sys.exit(run_bridge(args.prompt, args.resume))
    else:
        # If no prompt and no server, just exit or could default to server
        parser.print_help()
        sys.exit(0)
