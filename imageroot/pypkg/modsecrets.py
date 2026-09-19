#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

"""Module secrets, kept out of the agent environment.

state/environment is mirrored by the NS8 agent to Redis in plain text, so
passwords, tokens and keys are stored in state/passwords.env (mode 0600)
instead. The file is listed in etc/state-include.conf, loaded by the systemd
units with EnvironmentFile= and read by the actions through this module.
"""

import os
import sys

import agent

FILENAME = "passwords.env"


def _state_dir():
    return os.environ.get("AGENT_STATE_DIR") or os.path.expanduser("~/.config/state")


def path():
    return os.path.join(_state_dir(), FILENAME)


def read():
    """Return the secrets as a dictionary (empty if the file does not exist)."""
    try:
        return agent.read_envfile(path())
    except FileNotFoundError:
        return {}


def get(key, default=""):
    return read().get(key, default)


def write(values):
    """Merge values into the secrets file, keeping it private (0600)."""
    current = read()
    current.update({k: str(v) for k, v in values.items()})
    old_umask = os.umask(0o077)
    try:
        agent.write_envfile(path(), current)
    finally:
        os.umask(old_umask)
    os.chmod(path(), 0o600)
    return current


def ensure(defaults):
    """Store the given values only for keys that have no value yet."""
    current = read()
    missing = {k: v for k, v in defaults.items() if not current.get(k)}
    if missing or not os.path.exists(path()):
        write(missing)
    return missing


def migrate_from_env(keys, aliases=None):
    """Move legacy secrets from state/environment into the secrets file.

    aliases maps an extra name to an existing key, for containers that expect
    the same secret under another variable name.
    """
    env = agent.read_envfile(os.path.join(_state_dir(), "environment"))
    current = read()
    moved = {k: env[k] for k in keys if env.get(k) and not current.get(k)}
    if moved or not os.path.exists(path()):
        current = write(moved)
    if aliases:
        extra = {a: current[k] for a, k in aliases.items() if current.get(k) and current.get(a) != current.get(k)}
        if extra:
            write(extra)
    leftover = [k for k in keys if k in env]
    if leftover:
        agent.munset_env(leftover)
        print("moved out of state/environment: " + " ".join(leftover), file=sys.stderr)
    return leftover
