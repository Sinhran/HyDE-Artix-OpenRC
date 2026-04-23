#!/usr/bin/env bash
[[ $HYDE_SHELL_INIT -ne 1 ]] && eval "$(hyde-shell init)"

# Kill ALL portal processes. Starting fresh prevents stale portals from holding
# D-Bus names and causing "File exists" errors on restart.
killall -e xdg-document-portal  2>/dev/null
killall -e xdg-desktop-portal   2>/dev/null
killall -e xdg-desktop-portal-hyprland 2>/dev/null
# GTK and KDE backends are not needed on Hyprland and can interfere with
# the hyprland portal's ScreenCast implementation — leave them dead.
killall -e xdg-desktop-portal-gtk 2>/dev/null
killall -e xdg-desktop-portal-kde 2>/dev/null
sleep 1

# Wait for the D-Bus session socket to exist before starting portals.
# At boot, resetxdgportal.sh may run before dbus-init.sh has created the socket.
# Without this wait, xdg-desktop-portal-hyprland crashes with
# "Failed to open bus (No such file or directory)" and the portal log is overwritten.
if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bus_path="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
    bus_path="${bus_path%%,*}"
    waited=0
    while [ ! -S "$bus_path" ] && [ "$waited" -lt 10 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done
fi

# Resolve the library directory once.
if [ -d /run/current-system/sw/libexec ]; then
    libDir=/run/current-system/sw/libexec
else
    libDir=/usr/lib
fi

# Start the main xdg-desktop-portal FIRST. It acts as the session bus
# for all sub-portals and must be ready before xdph tries to connect.
app2unit.sh -t service "$libDir/xdg-desktop-portal" &
sleep 1

# Start the Hyprland portal SECOND. It handles ScreenCast (screen/window
# capture) and Screenshot portal calls using the hyprland-specific APIs.
# The -v flag enables debug logging to /tmp/portal-hyprland.log for
# troubleshooting screen share issues.
app2unit.sh -t service "$libDir/xdg-desktop-portal-hyprland" -v &
