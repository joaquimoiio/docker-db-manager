#!/usr/bin/env bash
# Shim de compatibilidade. O ponto de entrada real é ./dbm.
# Mantido para não quebrar atalhos/aliases existentes.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dbm" "$@"
