#!/bin/bash
# Keep the existing command entry point; selection is committed after verification.
exec php "$(dirname "$0")/driver-history.php" download "$1"
