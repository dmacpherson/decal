MODULE_DESC="fixture: applied once, then up to date"
module_add()    { echo "sk add $P_word" >> "$LS_TEST_LOG"; mkdir -p "$LS_USER_STATE"; : > "$LS_USER_STATE/sk.done"; }
module_remove() { echo "sk remove" >> "$LS_TEST_LOG"; rm -f "$LS_USER_STATE/sk.done"; }
module_status() { if [[ -e $LS_USER_STATE/sk.done ]]; then echo installed; else echo not-installed; fi; }
