# =============================================================================
# policies/sandbox_create.rego
# -----------------------------------------------------------------------------
# Open Policy Agent (OPA / Rego v1) policy that gates `create_env.sh` and
# POST /envs. Evaluated by the API *before* any side effects.
#
# Mirrors the Stage 4A SwiftDeploy policy pattern (allow + deny rules with
# explicit reasons). Violations BLOCK the request with HTTP 422.
#
# Evaluation:
#     opa eval --data policies/sandbox_create.rego \
#              --input  /tmp/create_input.json \
#              'data.sandbox.create.allow'
#
# Input shape (the API constructs this before calling OPA):
#     {
#       "name": "demo",
#       "ttl_minutes": 30,
#       "active_env_count": 4,
#       "max_active_envs": 10,
#       "default_ttl_minutes": 30,
#       "max_ttl_minutes": 240,
#       "reserved_names": ["nginx", "api", "daemon", "monitor", "platform"]
#     }
# =============================================================================

package sandbox.create

import rego.v1

# -----------------------------------------------------------------------------
# Allow only if there are zero violations.
# -----------------------------------------------------------------------------
default allow := false

allow if {
	count(violations) == 0
}

# -----------------------------------------------------------------------------
# Aggregate every violation into a single set the caller can render to the
# user. Each entry is {code, message}.
# -----------------------------------------------------------------------------
violations contains v if {
	some v in name_violations
}

violations contains v if {
	some v in ttl_violations
}

violations contains v if {
	some v in capacity_violations
}

# -----------------------------------------------------------------------------
# Name rules
# -----------------------------------------------------------------------------
name_violations contains {"code": "name_missing", "message": "name is required"} if {
	not input.name
}

name_violations contains {"code": "name_missing", "message": "name is required"} if {
	input.name == ""
}

name_violations contains {"code": "name_invalid", "message": "name must match ^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$"} if {
	input.name
	not regex.match(`^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$`, input.name)
}

name_violations contains {"code": "name_reserved", "message": sprintf("name '%s' is reserved for the platform", [input.name])} if {
	input.name in input.reserved_names
}

# -----------------------------------------------------------------------------
# TTL rules — bounded [1, max_ttl_minutes]; default applied upstream.
# -----------------------------------------------------------------------------
ttl_violations contains {"code": "ttl_too_low", "message": "ttl_minutes must be >= 1"} if {
	input.ttl_minutes < 1
}

ttl_violations contains {"code": "ttl_too_high", "message": sprintf("ttl_minutes must be <= %d", [input.max_ttl_minutes])} if {
	input.ttl_minutes > input.max_ttl_minutes
}

ttl_violations contains {"code": "ttl_not_integer", "message": "ttl_minutes must be an integer"} if {
	input.ttl_minutes
	round(input.ttl_minutes) != input.ttl_minutes
}

# -----------------------------------------------------------------------------
# Capacity rule — protect the host from being overrun.
# -----------------------------------------------------------------------------
capacity_violations contains {"code": "capacity_exhausted", "message": sprintf("active env count %d would exceed max %d", [input.active_env_count + 1, input.max_active_envs])} if {
	input.active_env_count >= input.max_active_envs
}
