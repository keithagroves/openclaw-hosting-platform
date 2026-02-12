ARG BASE_TAG="1.18.0"
FROM kasmweb/desktop:${BASE_TAG}

USER root

# Install OpenClaw via official installer (skip onboarding in non-interactive build)
ENV NPM_CONFIG_PREFIX=/usr/local \
    OPENCLAW_NO_PROMPT=1 \
    OPENCLAW_NO_ONBOARD=1 \
    PATH="/usr/local/bin:${PATH}"

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && curl -fsSL https://openclaw.ai/install.sh | bash \
  && command -v openclaw >/dev/null \
  && openclaw --version >/dev/null \
  && printf '%s\n' \
    "#!/bin/bash" \
    "set -euo pipefail" \
    "" \
    "MARKER=\"$HOME/.config/openclaw_onboarded\"" \
    "if [ ! -f \"$MARKER\" ]; then" \
    "  echo \"Loading OpenClaw...\"" \
    "  sleep 1" \
    "  openclaw onboard" \
    "  mkdir -p \"$HOME/.config\"" \
    "  touch \"$MARKER\"" \
    "fi" \
    "" \
    "# Keep the terminal open after onboarding" \
    "exec bash" \
    > /usr/local/bin/openclaw-onboard.sh \
  && chmod 0755 /usr/local/bin/openclaw-onboard.sh \
  && mkdir -p /etc/xdg/autostart \
  && printf '%s\n' \
    "[Desktop Entry]" \
    "Type=Application" \
    "Name=OpenClaw Onboard" \
    "Comment=Launch OpenClaw onboarding in a terminal" \
    "Exec=xfce4-terminal --maximize --command \"bash -lc 'openclaw-onboard.sh'\"" \
    "Terminal=false" \
    "X-GNOME-Autostart-enabled=true" \
    > /etc/xdg/autostart/openclaw-onboard.desktop \
  && chown -R kasm-user:kasm-user /home/kasm-user \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Kasm images expect these env vars at runtime (VNC_PW set per-customer)
ENV VNC_PW=""

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -skf https://localhost:6901/ >/dev/null || exit 1

USER kasm-user
