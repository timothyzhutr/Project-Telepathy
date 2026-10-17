#!/bin/sh
# Use the official pinned binary, with its cross-request history cache disabled.
: "${TELEPATHY_LLAMA_SERVER:?Set TELEPATHY_LLAMA_SERVER to the llama-server binary}"
exec "$TELEPATHY_LLAMA_SERVER" --cache-ram 0 "$@"
