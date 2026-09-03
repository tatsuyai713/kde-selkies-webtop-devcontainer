#!/bin/sh

# Shared PulseAudio compatibility endpoint selection.
# Ubuntu 26.04 uses pipewire-pulse in the user's runtime directory, while
# Ubuntu 22.04/24.04 use the standalone PulseAudio daemon in /run/pulse.

webtop_audio_backend() {
    webtop_version_id="$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-0}")"

    if [ -x /usr/bin/pipewire ] && { \
        [ ! -x /usr/bin/pulseaudio ] || \
        dpkg --compare-versions "${webtop_version_id}" ge 26.04; \
    }; then
        printf '%s\n' pipewire
    else
        printf '%s\n' pulseaudio
    fi
}

webtop_configure_pulse_runtime() {
    WEBTOP_AUDIO_UID="${1:-$(id -u)}"
    WEBTOP_AUDIO_BACKEND="$(webtop_audio_backend)"

    if [ "${WEBTOP_AUDIO_BACKEND}" = pipewire ]; then
        WEBTOP_PULSE_DIR="/run/user/${WEBTOP_AUDIO_UID}/pulse"
        unset PULSE_RUNTIME_PATH
    else
        WEBTOP_PULSE_DIR="/run/pulse"
        export PULSE_RUNTIME_PATH="${WEBTOP_PULSE_DIR}"
    fi

    WEBTOP_PULSE_SOCKET="${WEBTOP_PULSE_DIR}/native"
    export WEBTOP_AUDIO_BACKEND WEBTOP_PULSE_DIR WEBTOP_PULSE_SOCKET
    export PULSE_SERVER="unix:${WEBTOP_PULSE_SOCKET}"
}
