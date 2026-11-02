#!/bin/sh
# Claude Code hook (PreToolUse and PostToolUse on Write|Edit|MultiEdit):
# opens the Markdown file the agent is about to write, or just wrote, in
# QuickMD in the background, so live writing shows it being typed.
# Reads the hook's JSON on stdin; never blocks the tool.
file=$(plutil -extract tool_input.file_path raw -o - - 2>/dev/null) || exit 0
case "$file" in
    *.md | *.markdown | *.MD) ;;
    *) exit 0 ;;
esac
[ -f "$file" ] && open -g -a QuickMD "$file"
exit 0
