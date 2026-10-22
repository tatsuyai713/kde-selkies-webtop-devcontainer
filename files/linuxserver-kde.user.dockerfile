# syntax=docker/dockerfile:1

# Base image must be provided via --build-arg BASE_IMAGE=<image>
ARG BASE_IMAGE=scratch
FROM ${BASE_IMAGE}

ARG USER_NAME
ARG USER_UID
ARG USER_GID
ARG VIDEO_GID=""
ARG RENDER_GID=""
ARG HOST_HOSTNAME="Docker-Host"
ARG USER_LANGUAGE="en"
ARG USER_LANG_ENV="en_US.UTF-8"
ARG USER_LANGUAGE_ENV="en_US:en"

ENV HOME="/home/${USER_NAME}" \
    USER_NAME="${USER_NAME}" \
    HOST_HOSTNAME="${HOST_HOSTNAME}" \
    SHELL="/bin/bash" \
    LANG="${USER_LANG_ENV}" \
    LANGUAGE="${USER_LANGUAGE_ENV}" \
    LC_ALL="${USER_LANG_ENV}"

RUN --mount=type=secret,id=user_password \
  set -eu; \
  USER_PASSWORD="$(cat /run/secrets/user_password 2>/dev/null || true)"; \
  TARGET_USER="${USER_NAME}"; \
  TARGET_UID="${USER_UID}"; \
  TARGET_GID="${USER_GID}"; \
  if [ -z "${TARGET_UID}" ] || [ -z "${TARGET_GID}" ]; then echo "USER_UID/USER_GID must be provided (host UID/GID)"; exit 1; fi; \
  if [ -z "${USER_PASSWORD}" ]; then echo "USER_PASSWORD must be provided"; exit 1; fi; \
  echo "Using user=${TARGET_USER} uid=${TARGET_UID} gid=${TARGET_GID}"; \
  # ensure primary group named ${TARGET_USER} exists with TARGET_GID (allow non-unique gid to satisfy chown <user>:<user>) \
  if getent group "${TARGET_USER}" >/dev/null; then \
    groupmod -g "${TARGET_GID}" "${TARGET_USER}" || true; \
  else \
    groupadd -o -g "${TARGET_GID}" "${TARGET_USER}" 2>/dev/null || true; \
  fi; \
  if [ -n "${VIDEO_GID}" ]; then \
    if getent group video >/dev/null; then \
      groupmod -o -g "${VIDEO_GID}" video || true; \
    else \
      groupadd -o -g "${VIDEO_GID}" video || true; \
    fi; \
  fi; \
  if [ -n "${RENDER_GID}" ]; then \
    if getent group render >/dev/null; then \
      groupmod -o -g "${RENDER_GID}" render || true; \
    else \
      groupadd -o -g "${RENDER_GID}" render || true; \
    fi; \
  fi; \
  # remove any user that already has the desired UID to avoid conflicts \
  if getent passwd "${TARGET_UID}" >/dev/null; then \
    OLD_USER=$(getent passwd "${TARGET_UID}" | cut -d: -f1); \
    if [ "${OLD_USER}" != "${TARGET_USER}" ]; then \
      echo "UID ${TARGET_UID} in use by ${OLD_USER}, removing it"; \
      userdel -r "${OLD_USER}" || true; \
    fi; \
  fi; \
  # ensure common supplemental groups exist (similar to Ubuntu adduser) plus docker/sudo \
  for g in adm cdrom dip plugdev lpadmin lxd sudo docker users audio video render; do \
    getent group "$g" >/dev/null || groupadd "$g"; \
  done; \
  # set hostname to host-derived value (baked into image) \
  echo "${HOST_HOSTNAME}" > /etc/hostname; \
  # create or update main user matching host uid/gid (home=/home/<user>) \
  if ! getent passwd "${TARGET_USER}" >/dev/null; then \
    useradd -m -d "/home/${TARGET_USER}" -u "${TARGET_UID}" -g "${TARGET_USER}" -s /bin/bash "${TARGET_USER}"; \
  else \
    usermod -u "${TARGET_UID}" -g "${TARGET_USER}" -d "/home/${TARGET_USER}" "${TARGET_USER}"; \
    install -d -m 755 "/home/${TARGET_USER}"; \
  fi; \
  usermod -aG adm,cdrom,dip,plugdev,lpadmin,lxd,sudo,docker,users,audio,video,render "${TARGET_USER}"; \
  # Add www-data (nginx worker) to the user's group so nginx can serve files from host_home \
  usermod -aG "${TARGET_USER}" www-data 2>/dev/null || true; \
  echo "${TARGET_USER}:${USER_PASSWORD}" | chpasswd; \
  # store auth secret/hash for web login \
  SECRET_SALT=$(openssl rand -hex 16); \
  env TARGET_USER="${TARGET_USER}" TARGET_PW="${USER_PASSWORD}" SECRET_SALT="${SECRET_SALT}" \
    python3 -c "import json,hashlib,os;user=os.environ['TARGET_USER'];pw=os.environ['TARGET_PW'];salt=os.environ['SECRET_SALT'];pw_hash=hashlib.sha256((pw+salt).encode()).hexdigest();secret=hashlib.sha256((user+pw+salt).encode()).hexdigest();data={'user':user,'salt':salt,'pw_hash':pw_hash,'secret':secret};open('/etc/web-auth.json','w').write(json.dumps(data));os.chmod('/etc/web-auth.json',0o600)" ; \
  # ensure skeleton and Ubuntu-like bashrc for user (HOME=/home/<user>) and root \
  install -d -m 755 "/home/${TARGET_USER}"; \
  chown -R "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}"; \
  # create common XDG-style folders in the user's home \
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do \
    install -d -m 755 "/home/${TARGET_USER}/${d}"; \
    chown "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}/${d}"; \
  done; \
  DEFAULT_BASHRC="/usr/local/share/default_bashrc"; \
  printf '%s\n' \
    "# DEFAULT_BASHRC" \
    "# ~/.bashrc: executed by bash(1) for non-login shells." \
    "# If not running interactively, don't do anything" \
    "case \$- in" \
    "    *i*) ;;" \
    "      *) return;;" \
    "esac" \
    "HISTCONTROL=ignoreboth" \
    "shopt -s histappend" \
    "HISTSIZE=1000" \
    "HISTFILESIZE=2000" \
    "shopt -s checkwinsize" \
    "[ -x /usr/bin/lesspipe ] && eval \"\$(SHELL=/bin/sh lesspipe)\"" \
    "if [ -z \"\${debian_chroot:-}\" ] && [ -r /etc/debian_chroot ]; then" \
    "    debian_chroot=\$(cat /etc/debian_chroot)" \
    "fi" \
    "case \"\$TERM\" in" \
    "    xterm-color|*-256color) color_prompt=yes;;" \
    "esac" \
    "if [ -n \"\$force_color_prompt\" ]; then" \
    "    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then" \
    "        color_prompt=yes" \
    "    else" \
    "        color_prompt=" \
    "    fi" \
    "fi" \
    "if [ \"\$color_prompt\" = yes ]; then" \
    "    PS1=\"\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ \" " \
    "else" \
    "    PS1=\"\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\$ \" " \
    "fi" \
    "unset color_prompt force_color_prompt" \
    "case \"\$TERM\" in" \
    "xterm*|rxvt*)" \
    "    PS1=\"\\[\\e]0;\${debian_chroot:+(\$debian_chroot)}\\u@\\h: \\w\\a\\]\$PS1\"" \
    "    ;;" \
    "*)" \
    "    ;;" \
    "esac" \
    "if [ -x /usr/bin/dircolors ]; then" \
    "    test -r ~/.dircolors && eval \"\$(dircolors -b ~/.dircolors)\" || eval \"\$(dircolors -b)\"" \
    "    alias ls='ls --color=auto'" \
    "    alias grep='grep --color=auto'" \
    "    alias fgrep='fgrep --color=auto'" \
    "    alias egrep='egrep --color=auto'" \
    "fi" \
    "alias ll='ls -alF'" \
    "alias la='ls -A'" \
    "alias l='ls -CF'" \
    "if [ -f ~/.bash_aliases ]; then" \
    "    . ~/.bash_aliases" \
    "fi" \
    "if ! shopt -oq posix; then" \
    "  if [ -f /usr/share/bash-completion/bash_completion ]; then" \
    "    . /usr/share/bash-completion/bash_completion" \
    "  elif [ -f /etc/bash_completion ]; then" \
    "    . /etc/bash_completion" \
    "  fi" \
    "fi" \
    > "${DEFAULT_BASHRC}" \
  && cp "${DEFAULT_BASHRC}" "/home/${TARGET_USER}/.bashrc" \
  && cp "${DEFAULT_BASHRC}" /root/.bashrc \
  && chown "${TARGET_UID}:${TARGET_GID}" "/home/${TARGET_USER}/.bashrc" \
  && rm -f /etc/profile.d/00-ps1.sh /etc/profile.d/01-bashcomp.sh; \
  # reset sudoers to require password \
  sed -i 's/^%sudo\tALL=(ALL:ALL) NOPASSWD: ALL/%sudo\tALL=(ALL:ALL) ALL/' /etc/sudoers; \
  if ! grep -q "^%sudo\s\+ALL=(ALL:ALL)\s\+ALL" /etc/sudoers; then echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers; fi; \
  # Disable services unavailable/useless in a WSL webtop. BlueZ OBEX otherwise \
  # repeatedly activates a missing Evolution source registry and saturates the \
  # private session bus, which makes Plasma and Chrome appear frozen. \
  rm -f \
    /etc/xdg/autostart/packagekitd.desktop \
    /usr/share/dbus-1/system-services/org.freedesktop.PackageKit.service \
    /usr/share/dbus-1/system-services/org.freedesktop.UDisks2.service \
    /usr/share/dbus-1/services/org.bluez.obex.service; \
  install -d -m 755 /etc/dbus-1/system.d; \
  printf '%s\n' \
    '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"' \
    '"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">' \
    '<busconfig>' \
    '  <policy context="default">' \
    '    <deny send_destination="org.freedesktop.PackageKit"/>' \
    '    <deny send_destination="org.freedesktop.UDisks2"/>' \
    '  </policy>' \
    '</busconfig>' \
    > /etc/dbus-1/system.d/disable-packagekit.conf; \
  mkdir -p /defaults /app /opt/selkies-env && \
  chown -R "${TARGET_UID}:${TARGET_GID}" /defaults /app /opt/selkies-env

# optional Japanese locale and input (toggle via USER_LANGUAGE=jp)
RUN set -eux; \
  LANG_SEL="$(echo "${USER_LANGUAGE}" | tr '[:upper:]' '[:lower:]')" ; \
  if [ "${LANG_SEL}" = "jp" ]; then \
    UBUNTU_VERSION="$(. /etc/os-release && echo ${VERSION_ID})"; \
    if dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04"; then \
      # Ubuntu 26.04+ (Plasma 6): use fcitx5
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        language-pack-ja-base language-pack-ja im-config \
        fonts-noto-cjk fonts-noto-color-emoji \
        fcitx5 fcitx5-anthy fcitx5-config-qt kde-config-fcitx5 \
        fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 fcitx5-frontend-qt6 && \
      locale-gen ja_JP.UTF-8 && \
      update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP:ja LC_ALL=ja_JP.UTF-8 && \
      if [ -f /usr/share/plasma/layout-templates/org.kubuntu.desktop.defaultPanel/contents/layout.js ]; then \
        sed -i "s/addInputPanelFn( panel_obj );/\\/\\/ addInputPanelFn( panel_obj );/" /usr/share/plasma/layout-templates/org.kubuntu.desktop.defaultPanel/contents/layout.js; \
      fi && \
      apt-get clean && rm -rf /var/lib/apt/lists/*; \
      echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen || true; \
      echo 'LANG=ja_JP.UTF-8' > /etc/default/locale; \
      echo 'LANGUAGE=ja_JP:ja' >> /etc/default/locale; \
      echo 'LC_ALL=ja_JP.UTF-8' >> /etc/default/locale; \
      rm -f /etc/localtime; \
      ln -snf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime; \
      echo "Asia/Tokyo" > /etc/timezone; \
    else \
      # Ubuntu 22.04/24.04: use fcitx4
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        language-pack-ja-base language-pack-ja im-config \
        fonts-noto-cjk fonts-noto-color-emoji \
        fcitx fcitx-bin fcitx-data fcitx-table-all \
        fcitx-anthy fcitx-config-gtk \
        fcitx-frontend-gtk2 fcitx-frontend-gtk3 fcitx-frontend-qt5 \
        fcitx-module-dbus fcitx-module-kimpanel fcitx-module-x11 fcitx-module-lua fcitx-ui-classic \
        kde-config-fcitx && \
      locale-gen ja_JP.UTF-8 && \
      update-locale LANG=ja_JP.UTF-8 LANGUAGE=ja_JP:ja LC_ALL=ja_JP.UTF-8 && \
      apt-get clean && rm -rf /var/lib/apt/lists/*; \
      echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen || true; \
      echo 'LANG=ja_JP.UTF-8' > /etc/default/locale; \
      echo 'LANGUAGE=ja_JP:ja' >> /etc/default/locale; \
      echo 'LC_ALL=ja_JP.UTF-8' >> /etc/default/locale; \
      rm -f /etc/localtime; \
      ln -snf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime; \
      echo "Asia/Tokyo" > /etc/timezone; \
    fi; \
    printf '%s\n' \
      'XKBMODEL="jp106"' \
      'XKBLAYOUT="jp"' \
      'XKBVARIANT=""' \
      'XKBOPTIONS=""' \
      'BACKSPACE="guess"' \
      > /etc/default/keyboard; \
    install -d -m 755 /etc/X11/xorg.conf.d; \
    printf '%s\n' \
      'Section "InputClass"' \
      '    Identifier "system-keyboard"' \
      '    MatchIsKeyboard "on"' \
      '    Option "XkbLayout" "jp"' \
      '    Option "XkbModel" "jp106"' \
      '    Option "XkbVariant" ""' \
      '    Option "XkbOptions" ""' \
      'EndSection' \
      > /etc/X11/xorg.conf.d/00-keyboard.conf; \
    if dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04"; then \
      # KDE Wayland + Fcitx5: let KWin virtual keyboard manage startup.
      # Keep im-config from forcing GTK/QT IM env globally.
      im-config -n none || true; \
      install -d -m 755 /etc/xdg/autostart "/home/${USER_NAME}/.config/autostart"; \
      printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Exec=fcitx5 -d' \
        'Hidden=true' \
        'X-GNOME-Autostart-enabled=true' \
        'Name=fcitx5' \
        'Comment=Start Fcitx5 input method daemon' \
        > /etc/xdg/autostart/fcitx-autostart.desktop; \
      cp /etc/xdg/autostart/fcitx-autostart.desktop "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
      chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
      install -d -m 755 "/home/${USER_NAME}/.config/fcitx5"; \
      printf '%s\n' \
        '[Groups/0]' \
        'Name=Default' \
        'Default Layout=jp' \
        'DefaultIM=keyboard-jp' \
        '' \
        '[Groups/0/Items/0]' \
        'Name=keyboard-jp' \
        'Layout=jp' \
        '' \
        '[Groups/0/Items/1]' \
        'Name=anthy' \
        'Layout=jp' \
        '' \
        '[GroupOrder]' \
        '0=Default' \
        > "/home/${USER_NAME}/.config/fcitx5/profile"; \
      chown -R "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/fcitx5"; \
    else \
      im-config -n fcitx || true; \
      install -d -m 755 /etc/xdg/autostart "/home/${USER_NAME}/.config/autostart"; \
      printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Exec=fcitx -d' \
        'Hidden=false' \
        'X-GNOME-Autostart-enabled=true' \
        'Name=fcitx' \
        'Comment=Start Fcitx input method daemon' \
        > /etc/xdg/autostart/fcitx-autostart.desktop; \
      cp /etc/xdg/autostart/fcitx-autostart.desktop "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
      chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/autostart/fcitx-autostart.desktop"; \
    fi; \
    if ! dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04"; then \
      # fcitx4 (Ubuntu 24.04 and earlier) legacy per-user configuration
      install -d -m 755 "/home/${USER_NAME}/.config/fcitx"; \
      printf '%s\n' \
        '[Hotkey]' \
        'TriggerKey=CTRL_SPACE' \
        '' \
        '[Program]' \
        'ShareStateAmongWindow=All' \
        'DefaultInputMethodState=Active' \
        > "/home/${USER_NAME}/.config/fcitx/config"; \
      printf '%s\n' \
        '[Profile]' \
        'IMName=anthy' \
        'EnabledIMList=fcitx-keyboard-jp:True,anthy:True' \
        > "/home/${USER_NAME}/.config/fcitx/profile"; \
      chown -R "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/fcitx"; \
    fi; \
    printf '%s\n' \
      '[Layout]' \
      'DisplayNames=' \
      'LayoutList=jp' \
      'Model=jp106' \
      'Options=' \
      'ResetOldOptions=true' \
      'Use=true' \
      > "/home/${USER_NAME}/.config/kxkbrc"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/kxkbrc"; \
    install -d -m 755 "/home/${USER_NAME}/.config"; \
    printf '%s\n' \
      '[Formats]' \
      'LANG=ja_JP.UTF-8' \
      'LANGUAGE=ja_JP:ja' \
      'LC_DATE=ja_JP.UTF-8' \
      'LC_NUMERIC=ja_JP.UTF-8' \
      'LC_MONETARY=ja_JP.UTF-8' \
      'LC_MEASUREMENT=ja_JP.UTF-8' \
      'LC_ADDRESS=ja_JP.UTF-8' \
      'LC_NAME=ja_JP.UTF-8' \
      'LC_TELEPHONE=ja_JP.UTF-8' \
      'LC_PAPER=ja_JP.UTF-8' \
      'LC_COLLATE=ja_JP.UTF-8' \
      '' \
      '[Translations]' \
      'LANGUAGE=ja_JP:ja' \
      > "/home/${USER_NAME}/.config/plasma-localerc"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/plasma-localerc"; \
    printf '%s\n' \
      '[General]' \
      'OverrideLanguageLocale=ja_JP' \
      > "/home/${USER_NAME}/.config/plasma-locales-settings.json" || true; \
    if dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04"; then \
      printf '%s\n' \
        'LANG=ja_JP.UTF-8' \
        'LANGUAGE=ja_JP:ja' \
        'LC_ALL=ja_JP.UTF-8' \
        'GTK_IM_MODULE=fcitx' \
        'QT_IM_MODULE=fcitx' \
        'XMODIFIERS=@im=fcitx' \
        >> /etc/environment; \
    else \
      printf '%s\n' \
        'LANG=ja_JP.UTF-8' \
        'LANGUAGE=ja_JP:ja' \
        'LC_ALL=ja_JP.UTF-8' \
        'GTK_IM_MODULE=fcitx' \
        'QT_IM_MODULE=fcitx' \
        'XMODIFIERS=@im=fcitx' \
        >> /etc/environment; \
    fi; \
  fi

# Set fcitx environment variables globally when Japanese locale is selected
ARG USER_LANGUAGE
RUN LANG_SEL="$(echo "${USER_LANGUAGE}" | tr '[:upper:]' '[:lower:]')" ; \
  if [ "${LANG_SEL}" = "jp" ]; then \
    UBUNTU_VERSION="$(. /etc/os-release && echo ${VERSION_ID})"; \
    mkdir -p /etc/profile.d; \
    if dpkg --compare-versions "$UBUNTU_VERSION" ge "26.04"; then \
      printf '%s\n' \
        'export GTK_IM_MODULE=fcitx' \
        'export QT_IM_MODULE=fcitx' \
        'export XMODIFIERS="@im=fcitx"' \
        'export INPUT_METHOD=fcitx' \
        'export SDL_IM_MODULE=fcitx' \
        'export GLFW_IM_MODULE=fcitx' \
        > /etc/profile.d/99-fcitx-env.sh; \
    else \
      printf '%s\n' \
        'export GTK_IM_MODULE=fcitx' \
        'export QT_IM_MODULE=fcitx' \
        'export XMODIFIERS="@im=fcitx"' \
        'export INPUT_METHOD=fcitx' \
        'export SDL_IM_MODULE=fcitx' \
        'export GLFW_IM_MODULE=fcitx' \
        > /etc/profile.d/99-fcitx-env.sh; \
    fi; \
    chmod 644 /etc/profile.d/99-fcitx-env.sh; \
  fi

# create XDG user dirs and desktop shortcuts (Home/Trash)
RUN set -eux; \
  for d in Desktop Documents Downloads Music Pictures Videos Templates Public; do \
    install -d -m 755 "/home/${USER_NAME}/${d}"; \
    chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/${d}"; \
  done; \
  install -d -m 755 "/home/${USER_NAME}/.config"; \
  printf '%s\n' \
    'XDG_DESKTOP_DIR="$HOME/Desktop"' \
    'XDG_DOWNLOAD_DIR="$HOME/Downloads"' \
    'XDG_TEMPLATES_DIR="$HOME/Templates"' \
    'XDG_PUBLICSHARE_DIR="$HOME/Public"' \
    'XDG_DOCUMENTS_DIR="$HOME/Documents"' \
    'XDG_MUSIC_DIR="$HOME/Music"' \
    'XDG_PICTURES_DIR="$HOME/Pictures"' \
    'XDG_VIDEOS_DIR="$HOME/Videos"' \
    > "/home/${USER_NAME}/.config/user-dirs.dirs"; \
  printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Home' \
    'GenericName=Personal Files' \
    "URL=file:///home/${USER_NAME}" \
    'Icon=user-home' \
    'Type=Link' \
    > "/home/${USER_NAME}/Desktop/home.desktop"; \
  printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Trash' \
    'Comment=Contains removed files' \
    'Icon=user-trash-full' \
    'EmptyIcon=user-trash' \
    'URL=trash:/' \
    'Type=Link' \
    > "/home/${USER_NAME}/Desktop/trash.desktop"; \
  chmod 755 \
    "/home/${USER_NAME}/Desktop/home.desktop" \
    "/home/${USER_NAME}/Desktop/trash.desktop"; \
  chown "${USER_UID}:${USER_GID}" \
    "/home/${USER_NAME}/Desktop/home.desktop" \
    "/home/${USER_NAME}/Desktop/trash.desktop"

# KDE Plasma defaults for the desktop user: Kubuntu look-and-feel and
# double-click to open, from /defaults/kdeglobals in the base image.
RUN set -eux; \
  install -d -m 755 "/home/${USER_NAME}/.config"; \
  cp /defaults/kdeglobals "/home/${USER_NAME}/.config/kdeglobals"; \
  chown "${USER_UID}:${USER_GID}" "/home/${USER_NAME}/.config/kdeglobals"

# Container management desktop shortcuts (commit / flatten / stop); the tools live in the base image
COPY container-actions/container-commit.desktop /tmp/container-commit.desktop
COPY container-actions/container-flatten.desktop /tmp/container-flatten.desktop
COPY container-actions/container-stop.desktop /tmp/container-stop.desktop
RUN set -eux; \
  cp /tmp/container-commit.desktop "/home/${USER_NAME}/Desktop/container-commit.desktop"; \
  cp /tmp/container-flatten.desktop "/home/${USER_NAME}/Desktop/container-flatten.desktop"; \
  cp /tmp/container-stop.desktop "/home/${USER_NAME}/Desktop/container-stop.desktop"; \
  chmod 755 \
    "/home/${USER_NAME}/Desktop/container-commit.desktop" \
    "/home/${USER_NAME}/Desktop/container-flatten.desktop" \
    "/home/${USER_NAME}/Desktop/container-stop.desktop"; \
  chown "${USER_UID}:${USER_GID}" \
    "/home/${USER_NAME}/Desktop/container-commit.desktop" \
    "/home/${USER_NAME}/Desktop/container-flatten.desktop" \
    "/home/${USER_NAME}/Desktop/container-stop.desktop"; \
  rm -f /tmp/container-commit.desktop /tmp/container-flatten.desktop /tmp/container-stop.desktop
  
# Browser menu entries for the desktop user. The base image routes every launch
# path through the maintained wrappers (/usr/local/bin/google-chrome-wrapped,
# /usr/local/bin/wrapped-chromium) and installs dpkg hooks that keep it so; run
# the hooks once with the user's identity so the per-user copies exist too.
RUN set -eux; \
  for hook in /usr/local/bin/ensure-chromium-wrap /usr/local/bin/ensure-google-chrome-wrap; do \
    if [ -x "$hook" ]; then \
      USER_NAME="${USER_NAME}" USER_UID="${USER_UID}" USER_GID="${USER_GID}" "$hook"; \
    fi; \
  done

# Keep default USER=root so s6 init can modify system paths.
