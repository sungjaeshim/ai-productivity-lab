#!/bin/bash
# PAM sshd hook entrypoint kept at the legacy workspace path.
exec /root/.openclaw/scripts/ssh_login_notify.sh "$@"
