# server-motd.tape — generates docs/img/server-motd.gif
#
# Renders the SSH login banner exactly as the live host shows it (layout, glyphs,
# palette) from the fixed snapshot in scripts/demo/server-motd-demo.sh — the
# `ssh` typed in the GIF is a shell function that prints the snapshot; nothing connects.
#
# Build with:  vhs scripts/demo/server-motd.tape

Output docs/img/server-motd.gif

Set Theme { "name": "Sweet-Ambar-Blue", "background": "#0d0d0d", "foreground": "#e6e6e6", "cursor": "#f0a830", "selection": "#1c3a5e", "black": "#0d0d0d", "red": "#e06c75", "green": "#a3be8c", "yellow": "#f0a830", "blue": "#5fa8d3", "magenta": "#c678dd", "cyan": "#56b6c2", "white": "#abb2bf", "brightBlack": "#5c6370", "brightRed": "#ff7b85", "brightGreen": "#b5d39c", "brightYellow": "#ffc961", "brightBlue": "#7ec0ee", "brightMagenta": "#d68be4", "brightCyan": "#6bc8d0", "brightWhite": "#e6e6e6" }
Set FontFamily "Cascadia Mono NF"
Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 24
Set Shell "bash"
Set TypingSpeed 35ms
Set PlaybackSpeed 1.0

Hide
Type "ssh() { PS1=''; bash scripts/demo/server-motd-demo.sh; }; PS1='\[\e[38;5;244m\]laptop\[\e[0m\] $ '"
Enter
Type "clear"
Enter
Show

Sleep 700ms
Type "ssh operator@docker-host"
Sleep 400ms
Enter
Sleep 6s
