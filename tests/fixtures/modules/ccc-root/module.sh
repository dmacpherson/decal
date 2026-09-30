MODULE_DESC="fixture needing root"
MODULE_NEEDS_ROOT=1
module_add()    { srun touch "$LS_TEST_LOG.root"; echo "ccc add" >> "$LS_TEST_LOG"; }
module_remove() { echo "ccc remove" >> "$LS_TEST_LOG"; }
module_status() { echo "not-installed"; }
