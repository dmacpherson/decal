MODULE_DESC="apply fixture p1"
module_add()    { echo "p1 add $P_word" >> "$LS_TEST_LOG"; echo "p1 detail line"; warn "p1 heads-up"; if [[ $P_word == boom ]]; then echo "boom detail"; false; fi; }
module_remove() { echo "p1 remove" >> "$LS_TEST_LOG"; }
module_status() { echo "not-installed"; }
module_fetch()  { echo "p1 fetch" >> "$LS_TEST_LOG"; if [[ $P_word == fail ]]; then echo "fetch: download failed: https://x.invalid/y" >&2; return 1; fi; }
