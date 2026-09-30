# cat -> bat (plain output, no pager, so it behaves like cat)
if command -v bat >/dev/null; then alias cat='bat --style=plain --paging=never'; fi
