# Remembro Shell Integration
# Installed as `remembro-hook` — generates shell hook code and
# provides the `remembro-capture` helper for agent integration.
#
# Usage:
#   eval "$(remembro-hook init zsh)"     # In .zshrc
#   remembro-capture --source agent --cmd "..."  # From any agent

# ═══════════════════════════════════════════════════════════════
# remembro-hook  — Shell hook code generator
# ═══════════════════════════════════════════════════════════════

# Subcommand: init
# Generates the appropriate hook code for the shell.

__remembro_hook_init_zsh() {
	cat <<'HOOK'
# ── rememento: automatic command capture ─────────────────────
__REMEMBRO_SOCK="${XDG_RUNTIME_DIR:-$HOME/.remembro}/remembro/capture.sock"
__REMEMBRO_LAST_CMD=""
__REMEMBRO_LAST_TIME=0

__remembro_preexec() {
    local cmd="$1"
    local now
    now="$(date +%s%N)"

    # Skip short commands
    [[ ${#cmd} -lt 3 ]] && return

    # Skip no-ops
    [[ "$cmd" == "ls" || "$cmd" == "cd"* || "$cmd" == "pwd"    \
    || "$cmd" == "clear" || "$cmd" == "exit" || "$cmd" == "cd" ]] && return

    # Skip if prefixed with space (explicit opt-out)
    [[ "$cmd" == " "* ]] && return

    # Rate limit (500ms)
    local elapsed=$(( (now - __REMEMBRO_LAST_TIME) / 1000000 ))
    [[ $elapsed -lt 500 && "$cmd" == "$__REMEMBRO_LAST_CMD" ]] && return

    __REMEMBRO_LAST_CMD="$cmd"
    __REMEMBRO_LAST_TIME="$now"

    # Send to daemon via capture socket (non-blocking, best-effort)
    if [[ -S "$__REMEMBRO_SOCK" ]]; then
        {
            printf '{"jsonrpc":"2.0","method":"capture","params":{"source":"shell","cmd":%s}}\n' \
                "$(printf '%s' "$cmd" | jq -Rs .)" 2>/dev/null
        } | nc -U -w1 "$__REMEMBRO_SOCK" 2>/dev/null &
    fi
}

__remembro_precmd() {
    # Reserved for future use (exit code tracking, timing)
    :
}

preexec_functions+=(__remembro_preexec)
precmd_functions+=(__remembro_precmd)
HOOK
}

__remembro_hook_init_bash() {
	cat <<'HOOK'
# ── rememento: automatic command capture (bash) ──────────────
__REMEMBRO_SOCK="${XDG_RUNTIME_DIR:-$HOME/.remembro}/remembro/capture.sock"
__REMEMBRO_LAST_CMD=""
__REMEMBRO_LAST_TIME=0

__remembro_preexec() {
    local cmd="$1"
    local now
    now="$(date +%s%N)"

    [[ ${#cmd} -lt 3 ]] && return
    [[ "$cmd" == "ls" || "$cmd" == "cd"* || "$cmd" == "pwd" ]] && return
    [[ "$cmd" == " "* ]] && return

    local elapsed=$(( (now - __REMEMBRO_LAST_TIME) / 1000000 ))
    [[ $elapsed -lt 500 && "$cmd" == "$__REMEMBRO_LAST_CMD" ]] && return

    __REMEMBRO_LAST_CMD="$cmd"
    __REMEMBRO_LAST_TIME="$now"

    if [[ -S "$__REMEMBRO_SOCK" ]]; then
        printf '{"jsonrpc":"2.0","method":"capture","params":{"source":"shell","cmd":%s}}\n' \
            "$(printf '%s' "$cmd" | jq -Rs .)" 2>/dev/null \
            | nc -U -w1 "$__REMEMBRO_SOCK" 2>/dev/null &
    fi
}

if type -t __bp_install &>/dev/null; then
    # Use bash-preexec if already loaded
    preexec_functions+=(__remembro_preexec)
fi

# Fallback: PROMPT_COMMAND + DEBUG trap for bash without bash-preexec
if ! type -t __bp_install &>/dev/null; then
    __remembro_debug_trap() {
        local cmd="$BASH_COMMAND"
        # Only capture top-level commands, not in PROMPT_COMMAND
        [[ "$cmd" == "$PROMPT_COMMAND" ]] && return
        __remembro_preexec "$cmd"
    }
    trap '__remembro_debug_trap' DEBUG
fi
HOOK
}

__remembro_hook_init_fish() {
	cat <<'HOOK'
# ── rememento: automatic command capture (fish) ──────────────
function __remembro_capture --on-event fish_preexec
    set -l cmd $argv[1]
    set -l now (date +%s%N)

    # Skip short commands
    test (string length "$cmd") -lt 3; and return

    # Skip no-ops
    contains -- "$cmd" ls cd pwd clear exit; and return

    # Skip if starts with space
    string match -q ' *' "$cmd"; and return

    # Rate limit
    if set -q __remembro_last_time
        set -l elapsed (math "($now - $__remembro_last_time) / 1000000")
        test $elapsed -lt 500; and test "$cmd" = "$__remembro_last_cmd"; and return
    end

    set -g __remembro_last_cmd "$cmd"
    set -g __remembro_last_time $now

    # Send to daemon
    set -l sock (string join '/' $XDG_RUNTIME_DIR remembro capture.sock)
    if test -S "$sock"
        set -l json_cmd (printf '%s' $cmd | jq -Rs . 2>/dev/null)
        if test -n "$json_cmd"
            printf '{"jsonrpc":"2.0","method":"capture","params":{"source":"shell","cmd":%s}}\n' $json_cmd 2>/dev/null \
                | nc -U -w1 "$sock" 2>/dev/null &
        end
    end
end
HOOK
}

# ═══════════════════════════════════════════════════════════════
# remembro-capture  — Agent capture helper
# ═══════════════════════════════════════════════════════════════
# Usage: remembro-capture --source <source> --cmd "<command>"
#        remembro-capture --source opencode --cmd "docker compose up"
#        echo "docker build ..." | remembro-capture --source pipe

remembro_capture() {
	local source="" cmd=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--source)
			source="$2"
			shift 2
			;;
		--cmd)
			cmd="$2"
			shift 2
			;;
		--stdin) cmd="$(cat)" ;;
		*)
			echo "Unknown: $1" >&2
			return 1
			;;
		esac
	done

	# Support pipe: command | remembro-capture --source pipe
	if [[ -z "$cmd" && ! -t 0 ]]; then
		cmd="$(cat)"
	fi

	if [[ -z "$source" || -z "$cmd" ]]; then
		echo "Usage: remembro-capture --source <name> --cmd <command>" >&2
		echo "   or: echo '<command>' | remembro-capture --source pipe" >&2
		return 1
	fi

	local sock="${XDG_RUNTIME_DIR:-$HOME/.remembro}/remembro/capture.sock"
	local fifo="$HOME/.remembro/capture.fifo"

	# Try socket first, then FIFO
	if [[ -S "$sock" ]]; then
		printf '{"jsonrpc":"2.0","method":"capture","params":{"source":"%s","cmd":%s}}\n' \
			"$source" "$(printf '%s' "$cmd" | jq -Rs .)" |
			nc -U -w1 "$sock" 2>/dev/null && return 0
	fi

	if [[ -p "$fifo" ]]; then
		echo "$source:$cmd" >"$fifo" 2>/dev/null && return 0
	fi

	# Fallback: send via daemon control socket
	local daemon_sock="${XDG_RUNTIME_DIR:-$HOME/.remembro}/rembro.sock"
	if [[ -S "$daemon_sock" ]]; then
		printf '{"jsonrpc":"2.0","id":1,"method":"capture","params":{"source":"%s","cmd":%s}}\n' \
			"$source" "$(printf '%s' "$cmd" | jq -Rs .)" |
			nc -U -w1 "$daemon_sock" 2>/dev/null && return 0
	fi

	echo "remembro-capture: daemon not reachable" >&2
	return 1
}

# ═══════════════════════════════════════════════════════════════
# Main dispatcher
# ═══════════════════════════════════════════════════════════════

case "${1:-}" in
init)
	case "${2:-zsh}" in
	zsh) __remembro_hook_init_zsh ;;
	bash) __remembro_hook_init_bash ;;
	fish) __remembro_hook_init_fish ;;
	*)
		echo "Usage: remembro-hook init {zsh|bash|fish}" >&2
		exit 1
		;;
	esac
	;;
*)
	# If invoked directly (not sourced), run capture mode
	remembro_capture "$@"
	;;
esac
