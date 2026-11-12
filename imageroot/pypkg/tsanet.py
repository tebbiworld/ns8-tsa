#
# Copyright (C) 2026 tebbi
# SPDX-License-Identifier: GPL-3.0-or-later
#

"""Helpers for the optional client IP/network allowlist of the TSA route.

RFC 3161 timestamping is anonymous by design, so the service is public by
default. An operator may optionally restrict which client addresses may reach
it. The list is a set of IPv4/IPv6 addresses or CIDR networks, passed straight
to Traefik's ``ipAllowList`` middleware through ``agent.set_route`` and stored
(non-secret) in ``state/environment`` as the JSON variable
``TRAEFIK_IP_ALLOWLIST``.

An empty list means "no restriction"; it is kept as an explicit empty list
rather than an unset variable so that configure-module always sends
``ip_allowlist`` to set-route and thereby clears a previously set allowlist.
"""

import ipaddress
import json

ENV_KEY = "TRAEFIK_IP_ALLOWLIST"


def parse_allowlist(env_value):
    """Return the stored allowlist as a list of strings.

    Accepts the JSON array written by :func:`format_allowlist`. An unset,
    empty or malformed value is treated as "no restriction" (empty list), so a
    hand-edited or legacy environment can never break route configuration.
    """
    if not env_value:
        return []
    try:
        value = json.loads(env_value)
    except (ValueError, TypeError):
        return []
    if not isinstance(value, list):
        return []
    return [str(entry).strip() for entry in value if str(entry).strip()]


def format_allowlist(entries):
    """Serialise the allowlist to the JSON string stored in the environment."""
    return json.dumps(normalize_allowlist(entries))


def normalize_allowlist(entries):
    """Trim entries and drop empty ones, preserving order and duplicates-free.

    The operator's original spelling is kept (``10.0.0.0/8`` stays as typed);
    only surrounding whitespace and empty lines are removed.
    """
    seen = set()
    result = []
    for entry in entries or []:
        text = str(entry).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def validate_allowlist(entries):
    """Validate each entry as an IPv4/IPv6 address or CIDR network.

    Returns a list of invalid entries (empty when everything is valid). Host
    bits are allowed (``strict=False``) because Traefik's ``sourceRange``
    accepts both ``10.0.0.0/8`` and a bare address.
    """
    invalid = []
    for entry in normalize_allowlist(entries):
        try:
            ipaddress.ip_network(entry, strict=False)
        except ValueError:
            invalid.append(entry)
    return invalid
