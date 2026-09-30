MODULE_DESC="apply fixture p2"
module_add()    { echo "p2 add $P_word" >> "$LS_TEST_LOG"; }
module_remove() { echo "p2 remove" >> "$LS_TEST_LOG"; }
module_status() { echo "not-installed"; }
module_fetch()  { echo "p2 fetch" >> "$LS_TEST_LOG"; }
