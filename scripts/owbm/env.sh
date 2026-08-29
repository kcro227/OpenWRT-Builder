#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
   echo "This script must be sourced. Run: source ${BASH_SOURCE[0]}"
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OWBM_BIN="$PROJECT_ROOT/owbm"

if [[ ! -f "$OWBM_BIN" ]]; then
   echo "owbm binary not found. Building..."
   bash "$PROJECT_ROOT/build.sh" release
   if [[ $? -ne 0 ]]; then
       echo "Build failed. Exiting."
       return 1
   fi
fi

case ":${PATH}:" in
   *":$PROJECT_ROOT:"*)
       ;;
   *)
       export PATH="$PROJECT_ROOT:$PATH"
       ;;
 esac

source "$PROJECT_ROOT/scripts/completion.bash"
echo "owbm 已加入 PATH：$PROJECT_ROOT"
