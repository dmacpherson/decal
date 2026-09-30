MODULE_DESC="fixture that works"
module_add()    { echo "aaa add $PLATFORM" >> "$LS_TEST_LOG"; need_reboot; }
module_remove() { echo "aaa remove" >> "$LS_TEST_LOG"; }
module_status() { echo "installed"; }
module_capture(){ echo "aaa capture"; }
