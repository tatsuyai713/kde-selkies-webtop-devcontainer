# WSL2 GPU profiles: GL settings for programs started from a shell (terminals,
# docker exec) as well, matching the desktop session (startwm_wayland.sh).
case "${ENCODER:-${GPU_VENDOR:-}}" in
  intel-wsl|nvidia-wsl|amd-wsl)
    if [ "${WSL_ENVIRONMENT:-false}" = "true" ]; then
      # Mesa Kopper crashes GLX/EGL-on-X11 clients once the vgem node exists.
      export LIBGL_KOPPER_DISABLE=true
    fi
    ;;
esac
