MODULE_DESC="fixture without reboot"
module_add()    { echo "ddd add" >> "$LS_TEST_LOG"; }
module_remove() { echo "ddd remove" >> "$LS_TEST_LOG"; }
module_status() { echo "installed"; }
