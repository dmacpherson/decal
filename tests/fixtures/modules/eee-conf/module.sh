MODULE_DESC="fixture with profile config"
module_add()    { echo "eee add $P_word" >> "$LS_TEST_LOG"; }
module_remove() { echo "eee remove" >> "$LS_TEST_LOG"; }
module_status() { echo "not-installed"; }
