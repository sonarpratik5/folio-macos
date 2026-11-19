#!/bin/bash
# Agent QA harness driver (see docs/DEVELOPMENT.md "Agent QA harness").
#   scripts/qa.sh start [libdir]   build if needed, launch .build/Folio.app with FOLIO_QA_DIR=/tmp/folio-qa and a
#                                  disposable --library-path (default /tmp/folio-qa-lib-<timestamp>), wait until ready.
#   scripts/qa.sh <command ...>    post the command, wait up to 10s for /tmp/folio-qa/ack.txt, print it; non-zero on error/timeout.
# Commands (pages 1-based, text lines 0-based):
#   snapshot <name>                 PNG of the app window -> /tmp/folio-qa/<name>.png (snapshot.log notes the method)
#   open-sample | library | undo | redo | quit
#   tool <select|highlight|underline|text|note|eraser>      color <yellow|green|blue|pink>
#   mark-line <highlight|underline> <page> <lineIndex>      add-text <page> <x> <y> <text...> | commit-text
#   select-annotation <page> <index>
#   rotate <left|right>   zoom <in|out|fit-width|fit-page|actual>   page <n>   layout <single|continuous|two|two-continuous>
#   left-sidebar <on|off>  right-sidebar <on|off>
#   search <text>  (no text clears)   appearance <light|dark|system>   window <w> <h>
#   writing <on|off> | writing-text <text...> | return-passage | math-fixture (local synthetic answer, no provider)
#   section <all|opened|notes|starred|insights|conversations> | read-inspected | library-layout <list|grid>
#   assistant | reviews | concept-map (reader panel) | overview (Insights page)   select-line <page> <line>   ask-selection
#   selection-insights | explain-selection (explicit provider request) | provider <codex|claude> | keychain-check
#   skim <on|off>                    local adapted MiniLM; writes skim-state.json, never calls a provider
#   settings-shot <name> <codex|claude>   close-sheet   (AI commands never send a provider request)
set -euo pipefail
cd "$(dirname "$0")/.."
# Parallel runs: set FOLIO_QA_DIR (unique dir -> unique channel) and optionally FOLIO_QA_BIN (prebuilt FolioMac executable).
QA_DIR="${FOLIO_QA_DIR:-/tmp/folio-qa}"
APP=.build/Folio.app
CHANNEL="dev.folio.mac.qa.$(basename "$QA_DIR")"

if [[ "${1:-}" == start ]]; then
    lib="${2:-/tmp/folio-qa-lib-$(date +%s)}"
    BIN="${FOLIO_QA_BIN:-$PWD/$APP/Contents/MacOS/FolioMac}"
    if [[ -z "${FOLIO_QA_BIN:-}" ]] && [[ ! -x "$APP/Contents/MacOS/FolioMac" || -n "$(find Sources Package.swift -newer "$APP/Contents/MacOS/FolioMac" -name '*.swift' -o -newer "$APP/Contents/MacOS/FolioMac" -name Package.swift 2>/dev/null | head -1)" ]]; then
        scripts/build-app.sh debug >&2
    fi
    [[ -f "$QA_DIR/pid" ]] && kill "$(cat "$QA_DIR/pid")" 2>/dev/null || true
    rm -rf "$QA_DIR"; mkdir -p "$QA_DIR" "$lib"
    FOLIO_QA_DIR="$QA_DIR" nohup "$BIN" --library-path "$lib" >"$QA_DIR/app.log" 2>&1 &
    echo $! >"$QA_DIR/pid"
    for _ in $(seq 1 100); do [[ -f "$QA_DIR/ready.txt" ]] && { echo "$QA_DIR (library: $lib)"; exit 0; }; sleep 0.2; done
    echo "app did not become ready; see $QA_DIR/app.log" >&2; exit 1
fi

[[ $# -ge 1 ]] || { sed -n 2,19p "$0" >&2; exit 2; }
cmd="$*"
last() { [[ -f "$QA_DIR/ack.txt" ]] && cut -d' ' -f1 "$QA_DIR/ack.txt" || echo 0; }
before=$(last)
osascript -l JavaScript -e 'function run(a){ $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(a[1], a[0], $(), true); }' "$cmd" "$CHANNEL" >/dev/null
for _ in $(seq 1 100); do
    now=$(last)
    if [[ "$now" =~ ^[0-9]+$ && "$now" -gt "$before" ]]; then
        ack=$(cat "$QA_DIR/ack.txt"); echo "$ack"
        [[ "$ack" == *" error "* ]] && exit 1
        exit 0
    fi
    sleep 0.1
done
echo "timeout waiting for ack of: $cmd" >&2; exit 1
