# server-motd.tape — generates docs/img/server-motd.gif
#
# Renders the SSH login banner exactly as the live host shows it (layout, glyphs,
# palette) from the fixed snapshot in scripts/demo/server-motd-demo.sh — the
# `server` alias typed in the GIF is a shell function that prints the snapshot; nothing connects.
# LineHeight stays 1.0 so the block letters join up.
#
# Build with:  vhs scripts/demo/server-motd.tape
# Shared look for every demo (scripts/demo/themes/homepage.json): the Homepage dashboard
# palette, a window frame, FontSize 26 and the same `~ ❯` prompt. Width fits the content;
# the README shows each GIF at half its pixel width, so text is the same size in all of them.
# The prompt glyph (U+276F) is written as octal bytes: typed through vhs as a multibyte
# character it corrupts PS1 and leaks a raw colour code into the first frame.

Output docs/img/server-motd.gif

Set Theme {"name": "Homepage", "background": "#0c0c0c", "foreground": "#ededed", "cursor": "#8dbbd5", "selection": "#22313a", "black": "#0c0c0c", "red": "#f87171", "green": "#34d399", "yellow": "#e3b341", "blue": "#8dbbd5", "magenta": "#c4b5fd", "cyan": "#8dbbd5", "white": "#c4c4c4", "brightBlack": "#6b6b6b", "brightRed": "#fca5a5", "brightGreen": "#6ee7b7", "brightYellow": "#f5c96a", "brightBlue": "#a7cddd", "brightMagenta": "#ddd6fe", "brightCyan": "#a7cddd", "brightWhite": "#ffffff"}
Set FontFamily "Cascadia Mono NF, Cascadia Mono"
Set FontSize 26
Set LineHeight 1.0
Set Width 1180
Set Height 1200
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
Type "server() { PS1=''; bash scripts/demo/server-motd-demo.sh; }; PS1=$'\[\e[90m\]~\[\e[0m\] \[\e[34m\]\342\235\257\[\e[0m\] '"
Enter
Type "clear"
Enter
Show

Sleep 700ms
Type "server"
Sleep 400ms
Enter
Sleep 9s
