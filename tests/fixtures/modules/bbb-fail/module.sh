MODULE_DESC="fixture that fails"
module_add()    { false; echo "bbb after false" >> "$LS_TEST_LOG"; }
module_remove() { echo "bbb remove" >> "$LS_TEST_LOG"; }
module_status() { echo "not-installed"; }
