#!/usr/bin/env bash
#|---/ /+-------------------------+---/ /|#
#|--/ /-| Service restore script  |--/ /-|#
#|-/ /--| Prasanth Rangan         |-/ /--|#
#|/ /---+-------------------------+/ /---|#

scrDir="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
if ! source "${scrDir}/global_fn.sh"; then
    echo "Error: unable to source global_fn.sh..."
    exit 1
fi

flg_DryRun=${flg_DryRun:-0}
USE_SYSTEMD=false
if [ -d /run/systemd/system ]; then
    USE_SYSTEMD=true
fi

# Translate a systemctl command array to the appropriate init system command
# Sets RUN_CMD_IS_SHELL to true if the result needs shell evaluation
svc_cmd() {
    local context="$1"; shift
    local service="$1"; shift
    local -n out_arr="$1"; shift
    local cmd_args=("$@")

    RUN_CMD_IS_SHELL=false

    if $USE_SYSTEMD; then
        if [ "$context" = "user" ]; then
            out_arr=(systemctl --user "${cmd_args[@]}" "${service}.service")
        else
            out_arr=(sudo systemctl "${cmd_args[@]}" "${service}.service")
        fi
    else
        # OpenRC: translate systemctl subcommands
        local subcmd="${cmd_args[0]}"
        case "$subcmd" in
            enable)
                if [[ " ${cmd_args[*]} " == *" --now "* ]]; then
                    out_arr=("sudo rc-update add $service default && sudo rc-service $service start")
                    RUN_CMD_IS_SHELL=true
                else
                    out_arr=(sudo rc-update add "$service" default)
                fi
                ;;
            start)
                out_arr=(sudo rc-service "$service" start)
                ;;
            stop)
                out_arr=(sudo rc-service "$service" stop)
                ;;
            restart)
                out_arr=(sudo rc-service "$service" restart)
                ;;
            status)
                out_arr=(sudo rc-service "$service" status)
                ;;
            *)
                out_arr=(sudo rc-service "$service" "$subcmd")
                ;;
        esac
    fi
}

# Legacy function for backward compatibility with old system_ctl.lst format
handle_legacy_service() {
    local serviceChk="$1"

    if $USE_SYSTEMD; then
        if [[ $(systemctl list-units --all -t service --full --no-legend "${serviceChk}.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "${serviceChk}.service" ]]; then
            print_log -y "[skip] " -b "active " "Service ${serviceChk}"
        else
            print_log -y "enable " "Service ${serviceChk}"
            if [ "$flg_DryRun" -ne 1 ]; then
                sudo systemctl enable "${serviceChk}.service"
            fi
        fi
    else
        if rc-service "$serviceChk" status >/dev/null 2>&1; then
            print_log -y "[skip] " -b "active " "Service ${serviceChk}"
        else
            print_log -y "enable " "Service ${serviceChk}"
            if [ "$flg_DryRun" -ne 1 ]; then
                sudo rc-update add "$serviceChk" default
            fi
        fi
    fi
}

# Main processing
print_log -sec "services" -stat "restore" "system services..."

while IFS='|' read -r service context command || [ -n "$service" ]; do
    # Skip empty lines and comments
    [[ -z "$service" || "$service" =~ ^[[:space:]]*# ]] && continue

    # Trim whitespace
    service=$(echo "$service" | xargs)
    context=$(echo "$context" | xargs)
    command=$(echo "$command" | xargs)

    # Check if this is the new pipe-delimited format or legacy format
    if [[ -z "$context" ]]; then
        # Legacy format: service name only
        handle_legacy_service "$service"
    else
        # New format: service|context|command
        # Parse command into array to handle spaces properly
        read -ra cmd_array <<< "$command"

        if ! $USE_SYSTEMD && [ "$context" = "user" ]; then
            print_log -y "[skip] " "Service ${service} (user services not supported on non-systemd)"
            continue
        fi

        print_log -y "[exec] " "Service ${service} (${context}): $command"

        run_cmd=()
        RUN_CMD_IS_SHELL=false
        svc_cmd "$context" "$service" run_cmd "${cmd_array[@]}"

        if [ "$flg_DryRun" -ne 1 ]; then
            if [ "$context" = "user" ]; then
                if [[ -n "${DBUS_SESSION_BUS_ADDRESS}" ]] && [[ -n $XDG_RUNTIME_DIR ]]; then
                    if [ "$RUN_CMD_IS_SHELL" = "true" ]; then
                        sh -c "${run_cmd[0]}"
                    else
                        "${run_cmd[@]}"
                    fi
                else
                    print_log -sec "services" -stat "error" "DBUS_SESSION_BUS_ADDRESS or XDG_RUNTIME_DIR not set for user service" -y " skipping"
                fi
            else
                if [ "$RUN_CMD_IS_SHELL" = "true" ]; then
                    sh -c "${run_cmd[0]}"
                else
                    "${run_cmd[@]}"
                fi
            fi
        else
            print_log -c "[dry-run] " "${run_cmd[*]}"
        fi
    fi

done < "${scrDir}/restore_svc.lst"

print_log -sec "services" -stat "completed" "service updated successfully"
