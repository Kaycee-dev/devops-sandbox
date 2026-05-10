# =============================================================================
# policies/sandbox_outage.rego
# -----------------------------------------------------------------------------
# Gates `simulate_outage.sh` and POST /envs/{id}/outage. The hard constraint
# from the brief — "never run simulation against the Nginx or daemon
# container" — lives HERE (defence in depth: bash also enforces it).
#
# Input shape:
#     {
#       "env_id": "env-1a2b3c4d",
#       "container_name": "sandbox-env-1a2b3c4d-app",
#       "mode": "crash",
#       "platform_container_names": [
#         "sandbox-nginx", "sandbox-api", "sandbox-daemon", "sandbox-monitor"
#       ],
#       "env_status": "running",
#       "allowed_modes": ["crash", "pause", "network", "recover", "stress"]
#     }
# =============================================================================

package sandbox.outage

import rego.v1

default allow := false

allow if {
	count(violations) == 0
}

violations contains v if { some v in target_violations }
violations contains v if { some v in mode_violations }
violations contains v if { some v in state_violations }

# -----------------------------------------------------------------------------
# THE BIG RULE: never simulate against a platform container.
# This is the implementation of the brief's explicit guard requirement.
# -----------------------------------------------------------------------------
target_violations contains {"code": "target_protected", "message": sprintf("'%s' is a platform container — outage simulation is forbidden", [input.container_name])} if {
	input.container_name in input.platform_container_names
}

target_violations contains {"code": "target_protected", "message": "container names starting with 'sandbox-nginx', 'sandbox-api', 'sandbox-daemon', or 'sandbox-monitor' are protected"} if {
	some prefix in ["sandbox-nginx", "sandbox-api", "sandbox-daemon", "sandbox-monitor"]
	startswith(input.container_name, prefix)
}

target_violations contains {"code": "env_id_invalid", "message": "env_id must match ^env-[0-9a-f]{8}$"} if {
	not regex.match(`^env-[0-9a-f]{8}$`, input.env_id)
}

# -----------------------------------------------------------------------------
# Mode rules
# -----------------------------------------------------------------------------
mode_violations contains {"code": "mode_invalid", "message": sprintf("mode '%s' is not in allowed set", [input.mode])} if {
	not input.mode in input.allowed_modes
}

mode_violations contains {"code": "mode_missing", "message": "mode is required"} if {
	not input.mode
}

# -----------------------------------------------------------------------------
# State rules — can't simulate on an env that's mid-creation or being torn down.
# -----------------------------------------------------------------------------
state_violations contains {"code": "env_not_ready", "message": sprintf("env is in state '%s'; simulation requires running|degraded", [input.env_status])} if {
	not input.env_status in {"running", "degraded"}
}
