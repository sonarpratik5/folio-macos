# Adapted MiniLM for local Skim highlights

This is the existing Folio full-text-adapted Scim MiniLMv2-L6-H384 checkpoint, not the unchanged web default and not BERT-Tiny. Six layers, hidden size 384, five labels in order: background, method, objective, other, result. Goal is the display label for objective.

The ignored `AdaptedMiniLM.mlmodelc` is a compiled FP16 Core ML model (~46 MB). `manifest.json` records the source safetensors SHA-256, native/PyTorch verification and synthetic tokenizer fixtures. `vocab.txt` is the matching uncased WordPiece vocabulary. The app uses only native Core ML, without Python, a server or a provider request. Bundling the model does not make it a PDF attachment or a saved annotation.

## Reproduce

From the native repository, create the build-only environment and supply an existing adapted checkpoint:

```sh
UV_CACHE_DIR="$PWD/.build/uv-cache" uv venv --python 3.12 .build/skim-venv
UV_CACHE_DIR="$PWD/.build/uv-cache" uv pip install --python .build/skim-venv/bin/python torch==2.7.0 transformers==4.57.6 coremltools==9.0 'numpy<2.3'
HF_HUB_OFFLINE=1 TOKENIZERS_PARALLELISM=false .build/skim-venv/bin/python scripts/export-skim.py /path/to/scim-adapted
FOLIO_SWIFTPM_UNSANDBOXED=1 scripts/build-app.sh debug
```

macOS Core ML compilation requires host service access. The exporter reads only the supplied checkpoint, verifies synthetic native predictions against PyTorch, and compiles into `Models/Skim`. It does not download, train or upload papers. Runtime resources are copied into the app bundle; SwiftPM development/test binaries use this repository's `Models/Skim`. Default packaging of a fresh clone requires the adapted checkpoint/export; the source code is portable, but this checkpoint is not fetched automatically. A missing model reports an error without a different model fallback. Source-only CI explicitly sets `FOLIO_SOURCE_ONLY_BUILD=1` to verify app packaging without the untracked model and skips the two model-inference tests when weights are absent. Normal packaging remains strict.

## Provenance and limitations

Upstream: [Scim](https://github.com/rayfok/scim), [MiniLM](https://github.com/microsoft/unilm/tree/master/minilm), Apache-2.0. Adaptation used CSAbstruct replay and a tiny 62-sentence full-text training pilot; it is not a broadly validated scientific classifier. Goal versus contribution and prior-work findings remain difficult. The earlier single-paper evaluation used provisional AI labels and does not establish human accuracy. Source checkpoint hash and conversion labels are in the manifest; they establish conversion identity, not scientific validity. The original research is described in the web repository's FACET_CLASSIFIER_RESEARCH document; the web app is not a runtime dependency.

The exporter uses a finite negative attention mask to avoid FP16 GPU overflow and verifies native outputs against the original PyTorch masking path. Native inference uses consecutive sentence windows with three-sentence overlap (rather than resetting at every paragraph), at most 80 WordPieces per sentence and 512 positions per window. Background/Other are not shown. Display selects the highest-scoring eligible sentence at probability ≥0.5 per text block (up to three sentences, split at blank paragraphs/pages). Scores are uncalibrated. There are no section-based label bans. PDF extraction, sentence segmentation and runtime quantization differences still require representative human-reviewed evaluation. No accuracy improvement over the web pipeline is claimed by the conversion checks.
