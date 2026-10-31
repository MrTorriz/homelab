# alerting.tape — generates docs/img/alerting.gif
#
# Shows the event-driven detection layer: fail2ban's sshd jail, then the ntfy
# event feed. Both commands are shell functions that print the sanitised output
# of scripts/demo/alerting-demo.sh; nothing touches a real service.
#
# Build with:  vhs scripts/demo/alerting.tape
# Shared look for every demo (scripts/demo/themes/homepage.json): the Homepage dashboard
# palette, a window frame, FontSize 26 and the same `~ ❯` prompt. Width fits the content;
# the README shows each GIF at half its pixel width, so text is the same size in all of them.
# The prompt glyph (U+276F) is written as octal bytes: typed through vhs as a multibyte
# character it corrupts PS1 and leaks a raw colour code into the first frame.

Output docs/img/alerting.gif

Set Theme {"name": "Homepage", "background": "#0c0c0c", "foreground": "#ededed", "cursor": "#8dbbd5", "selection": "#22313a", "black": "#0c0c0c", "red": "#f87171", "green": "#34d399", "yellow": "#e3b341", "blue": "#8dbbd5", "magenta": "#c4b5fd", "cyan": "#8dbbd5", "white": "#c4c4c4", "brightBlack": "#6b6b6b", "brightRed": "#fca5a5", "brightGreen": "#6ee7b7", "brightYellow": "#f5c96a", "brightBlue": "#a7cddd", "brightMagenta": "#ddd6fe", "brightCyan": "#a7cddd", "brightWhite": "#ffffff"}
Set FontFamily "Cascadia Mono NF, Cascadia Mono"
Set FontSize 26
Set LineHeight 1.2
Set Width 1400
Set Height 900
Set Padding 36
Set Margin 40
Set MarginFill "#050505"
Set WindowBar Colorful
Set WindowBarSize 44
Set BorderRadius 14
Set Shell "bash"
Set TypingSpeed 55ms
Set PlaybackSpeed 1.0

Hide
Type "export NTFY_TOPIC=homelab-alerts NTFY_DRY_RUN=1 HOMELAB_IP=host.example.test HOSTNAME=homelab; sudo() { bash scripts/demo/alerting-demo.sh fail2ban; }; ntfy() { bash scripts/demo/alerting-demo.sh feed; }; PS1=$'\[\e[90m\]~\[\e[0m\] \[\e[34m\]\342\235\257\[\e[0m\] '"
Enter
Type "clear"
Enter
Show

Sleep 600ms
Type "sudo fail2ban-client status sshd"
Sleep 400ms
Enter
Sleep 4s
Type "ntfy tail homelab-alerts --since 24h"
Sleep 400ms
Enter
Sleep 6s
