#!/bin/bash
# Keep the existing command entry point; selection is committed after verification.
# The legacy WebGUI log displays stdout; include PHP errors and wget progress there.
exec php "$(dirname "$0")/driver-history.php" download "$1" 2>&1
