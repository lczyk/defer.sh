#!/usr/bin/env bash
# this file is the 'source'able version of defer
# it can be used in other scripts to provide the 'defer' function
# https://gist.github.com/lczyk/334619a32eaaf17443d404ecc5fc0ee6

# hide our own source-time xtrace so `bash -x caller.sh` isn't drowned in defer
# internals (set DEFER_DEBUG to keep it). the redirected group sends even these
# two lines' trace to /dev/null; xtrace is restored at the very end of the file.
{ _defer_src_x=$-; ${DEFER_DEBUG:+:} set +x; } 2>/dev/null

# Meant to be sourced, not executed. Refuse direct execution (except --test).
if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" != "--test" ]]; then
    printf "This file should be sourced, not executed\n" >&2
    exit 1
fi

if [[ -z "${__DEFER_SH__:-}" ]]; then
    # spellchecker: ignore Marcin Konowalczyk lczyk subshell

    __DEFER_SH_VERSION__='2.0.0'

    # Defers execution of a command until the specified signal(s) is received.
    # Multiple commands can be deferred to the same signal, and they will be
    # executed in reverse order of deferral (LIFO).
    #
    # Written by Marcin Konowalczyk @lczyk
    # Based on a post by Richard Hansen:
    # https://stackoverflow.com/a/7287873/2531987
    # CC-BY-SA 3.0
    function defer() {
        # suppress our own xtrace (set DEFER_DEBUG to keep it). 2>/dev/null on the brace
        # group swallows the trace of both inner commands (xtrace -> fd 2), so capture +
        # set +x cost zero trace lines and _defer_xtrace stays local -- no global, no
        # here-string. restore manually (not a trap) so the caller's RETURN trap survives;
        # it runs after set +x, so it's untraced too. (DEFER_DEBUG flips set +x to a : noop.)
        { local _defer_xtrace=$-; ${DEFER_DEBUG:+:} set +x; } 2>/dev/null
        # NOTE: `|| set -x` not `&& set -x` so _defer_restore always returns 0 --
        # a nonzero return trips a caller's set -e on the bare call below. inverting
        # the test keeps it untraced (set -x still runs only when xtrace was on).
        _defer_restore() { unset -f _defer_restore; [[ $_defer_xtrace != *x* ]] || set -x; }

        (($#)) || { printf "defer: usage: defer <cmd> <signal>...\n" >&2; _defer_restore; return 2; }
        local defer_cmd="$1"; shift
        defer_cmd="${defer_cmd%"${defer_cmd##*[!;[:space:]]}"}" # strip trailing ; and whitespace
        (($#)) || { printf "defer: no signal name given\n" >&2; _defer_restore; return 2; }
        # shellcheck disable=SC2317,SC2329 # invoked indirectly via eval
        _defer_extract() { printf '%s\n' "${3:-}"; }
        local defer_name new_cmd existing_cmd rc=0 marker
        for defer_name in "$@"; do
            # a no-op marker: invisible normally, but under set -x it prints a
            # labelled header so the deferred commands don't appear out of nowhere.
            marker=$(printf ": 'defer: running %s handlers';" "$defer_name")
            existing_cmd=$(eval "_defer_extract $(trap -p "${defer_name}")")
            existing_cmd=${existing_cmd#'defer_status=$?; '} # remove leading status capture
            existing_cmd=${existing_cmd#"$marker "}          # remove our xtrace marker
            new_cmd="$(printf '%s' 'defer_status=$?; '; printf '%s ' "${marker}"; printf '%s; ' "${defer_cmd}"; printf '%s' "${existing_cmd}")"
            trap -- "$new_cmd" "$defer_name" || { printf "Error: Unable to modify trap for %s\n" "$defer_name" >&2; rc=1; }
        done
        unset -f _defer_extract
        _defer_restore
        return $rc
    }
    declare -f -t defer

    ############################################################################
    # Self-test when run directly with --test
    # bash defer.sh --test
    if [[ "${#BASH_SOURCE[@]}" -eq 1 && "${BASH_SOURCE[0]}" == "$0" && "$1" == "--test" ]]; then
        ###################### usage examples ######################
        function test_basic() {
            test_var=0
            defer "test_var=1" USR1
            test "$test_var" -eq 0 || return 1
            kill -USR1 $$
            test "$test_var" -eq 1 || return 1
        }

        function test_defer_order() {
            output=""
            defer "output+='1'" USR1
            defer "output+='2'" USR1
            defer "output+='3'" USR1
            kill -USR1 $$
            test "$output" = "321" || return 1
        }

        function test_captures_status() {
            # When using $? we see the status of the previous deferred command
            test "$(
                defer 'echo $?' EXIT
                defer 'false' EXIT
                exit 99
            )" -eq 1 || return 1
            # But $defer_status captures the status of the command that triggered the trap
            # shellcheck disable=SC2016
            test "$(
                defer 'echo $defer_status' EXIT
                defer 'false' EXIT
                exit 99
            )" -eq 99 || return 1
        }

        function test_defer_on_function_exit() {
            test_var=0
            function f() { defer "test_var=1" EXIT; test_var=2; }; f
            # EXIT trap does not run until the script exits, so the value is 2
            test "$test_var" -eq 2 || return 1
        }

        function test_defer_on_function_return() {
            test_var=0
            function f() { defer "test_var=1" RETURN; test_var=2; }; f
            # RETURN trap runs when the function returns, so the value is 1
            test "$test_var" -eq 1 || return 1
        }

        function test_defer_in_function_in_subshell() {
            function f() { printf "a"; defer "printf \"b\"" EXIT; };
            test_var=$(f)
            test "$test_var" = "ab" || return 1
        }

        ################# edge-case / regression ###################
        function test_tolerates_trailing_semicolon() {
            test_var=0
            defer "test_var=1;" USR1
            test "$test_var" -eq 0 || return 1
            kill -USR1 $$
            test "$test_var" -eq 1 || return 1
        }

        function test_tolerates_multiple_trailing_semicolons() {
            test_var=0
            defer "test_var=1;;" USR1
            test "$test_var" -eq 0 || return 1
            kill -USR1 $$
            test "$test_var" -eq 1 || return 1
        }

        function test_tolerates_trailing_whitespace() {
            test_var=0
            defer "test_var=1; " USR1
            test "$test_var" -eq 0 || return 1
            kill -USR1 $$
            test "$test_var" -eq 1 || return 1
        }

        function test_no_caller_namespace_leak() {
            new_cmd="keep"; defer_name="keep"; existing_cmd="keep"
            defer "true" USR1
            test "$new_cmd" = "keep" || return 1
            test "$defer_name" = "keep" || return 1
            test "$existing_cmd" = "keep" || return 1
            kill -USR1 $$
        }

        function test_no_signal_returns_error() {
            defer "echo nope" 2>/dev/null
            test "$?" -ne 0 || return 1
        }

        function test_no_args_under_set_u() {
            # must give a clean usage error, not a bash '$1: unbound variable' crash
            local err; err=$( set -u; defer 2>&1 )
            case "$err" in *unbound*) return 1;; esac
            test -n "$err" || return 1
        }

        function test_returns_error_on_bad_signal() {
            defer "true" NOTASIGNAL 2>/dev/null
            test "$?" -ne 0 || return 1
        }

        function test_child_process_can_source() {
            # regression test: __DEFER_SH__ must not be exported
            local got
            got=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c '
                source "$DEFER_SH_PATH"
                bash -c "source \"\$DEFER_SH_PATH\"; type -t defer"
            ')
            test "$got" = "function" || return 1
        }

        function test_resourcing_preserves_traps() {
            # sourcing defer.sh a second time must be a safe no-op: an already-registered
            # trap survives the re-source, so deferred commands keep their LIFO order.
            # note: run in a child so $$ is its own pid -- bash 3.2 has no BASHPID
            local got
            got=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c '
                source "$DEFER_SH_PATH"
                o=""
                defer "o+=A" USR1
                source "$DEFER_SH_PATH"   # second source must not disturb the trap
                defer "o+=B" USR1
                kill -USR1 $$
                echo "$o"
            ')
            test "$got" = "BA" || return 1
        }

        function test_xtrace_suppression_preserves_caller_return_trap() {
            # regression test. the xtrace-hiding path must not clobber RETURN trap of the caller
            # shellcheck disable=SC2016
            local body='source "$DEFER_SH_PATH"; o=""
                f() { trap "o+=R" RETURN; defer "true" EXIT; }'
            local quiet noisy
            quiet=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c "$body"'
                f; trap - EXIT; echo "$o"')
            noisy=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c "$body"'
                set -x; f; set +x; trap - EXIT; echo "$o"' 2>/dev/null)
            test -n "$quiet" || return 1          # sanity: caller trap fired at all
            test "$quiet" = "$noisy" || return 1  # xtrace path must not change it
        }

        function test_xtrace_restored_under_custom_ifs() {
            # regression: restoring xtrace must not depend on IFS containing a space.
            # an unquoted ${_defer_xtrace:+set -x} word-splits "set -x" into two words
            # only when IFS has a space -- under IFS=: (or IFS=$'\n', etc.) it stays one
            # word, fails to run, and xtrace is silently lost. (run in a child so the
            # set -x output stays isolated; trace goes to stderr, the token to stdout.)
            local got
            got=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c '
                source "$DEFER_SH_PATH"
                IFS=:
                set -x
                defer "true" EXIT
                case $- in *x*) echo RESTORED;; *) echo LOST;; esac
            ' 2>/dev/null)
            test "$got" = "RESTORED" || return 1
        }

        function test_set_e_safe() {
            # regression: a caller with set -e must not abort when calling defer.
            # _defer_restore must not return nonzero -- otherwise the bare call to
            # it inside defer trips set -e, killing the caller mid-function (after
            # the trap is registered but before defer returns). run in a child that
            # exits 0 so the full EXIT chain has to fire.
            local got
            got=$(DEFER_SH_PATH="${BASH_SOURCE[0]}" bash -c '
                set -e
                source "$DEFER_SH_PATH"
                defer "echo c" EXIT
                defer "echo b" EXIT
                defer "echo a" EXIT
                echo go
            ')
            test "$got" = $'go\na\nb\nc' || return 1
        }

        # no color when NO_COLOR is set (any value) or stdout is not a tty
        if [[ -n "${NO_COLOR+x}" || ! -t 1 ]]; then
            c_green="" c_red="" c_reset=""
        else
            c_green=$'\e[32m' c_red=$'\e[31m' c_reset=$'\e[0m'
        fi

        status=0

        # fiscover test functions in declaration order (declare -F sorts alphabetically)
        # spellchecker: ignore mpass mfail
        while read -r line; do
            [[ $line =~ ^[[:space:]]*function[[:space:]]+(test_[A-Za-z0-9_]+) ]] || continue
            test_func="${BASH_REMATCH[1]}"
            printf "Running %s... " "$test_func"
            if $test_func; then
                printf "%spass%s\n" "$c_green" "$c_reset"
            else
                printf "%sfail%s\n" "$c_red" "$c_reset"
                status=1
            fi
        done < "${BASH_SOURCE[0]}"

        if [[ $status -eq 0 ]]; then
            printf "%sSelf-test passed%s\n" "$c_green" "$c_reset"
        else
            printf "%sSelf-test failed%s\n" "$c_red" "$c_reset"
        fi
    fi

    # no not export __DEFER_SH__. it would leak into child processes
    # (which don't inherit the function) and stop them sourcing defer.
    __DEFER_SH__=1
fi

# restore the caller's xtrace (untraced: x is still off here, so set -x prints
# nothing). unset before set -x so the cleanup leaves no trace line either.
case $_defer_src_x in *x*) unset _defer_src_x; set -x;; *) unset _defer_src_x;; esac