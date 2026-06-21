#!/bin/bash
# Double-click this on macOS to manage your Working Folders shelf.
# (It just opens the menu in working-folders.sh.)
cd "$(dirname "$0")" || exit 1
exec /bin/bash "./working-folders.sh" menu
