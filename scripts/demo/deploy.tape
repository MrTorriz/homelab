# deploy.tape — generates docs/img/deploy.gif
#
# Demonstrates scripts/deploy.sh — idempotent rsync from git → live with
# conditional service reloads. Uses scripts/demo/deploy-demo.sh so the
# recording does not actually rsync or restart anything.
#
# Build with:  vhs scripts/demo/deploy.tape

Output docs/img/deploy.gif

Set Theme { "name": "Sweet-Ambar-Blue", "background": "#0d0d0d", "foreground": "#e6e6e6", "cursor": "#f0a830", "selection": "#1c3a5e", "black": "#0d0d0d", "red": "#e06c75", "green": "#a3be8c", "yellow": "#f0a830", "blue": "#5fa8d3", "magenta": "#c678dd", "cyan": "#56b6c2", "white": "#abb2bf", "brightBlack": "#5c6370", "brightRed": "#ff7b85", "brightGreen": "#b5d39c", "brightYellow": "#ffc961", "brightBlue": "#7ec0ee", "brightMagenta": "#d68be4", "brightCyan": "#6bc8d0", "brightWhite": "#e6e6e6" }
Set FontFamily "Cascadia Mono"
Set FontSize 28
Set Width 1280
Set Height 720
Set Padding 24
Set Shell "bash"
Set TypingSpeed 35ms
Set PlaybackSpeed 1.0

Hide
Type "export NTFY_TOPIC=homelab-alerts NTFY_DRY_RUN=1 HOMELAB_IP=192.168.1.10 HOSTNAME=homelab"
Enter
Type "clear"
Enter
Show

Sleep 600ms
Type "./scripts/demo/deploy-demo.sh"
Sleep 400ms
Enter
Sleep 6s
