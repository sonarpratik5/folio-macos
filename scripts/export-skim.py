"""Convert an existing scim-adapted checkpoint; never downloads or retrains a model.

Build-only environment: uv pip install torch==2.7.0 transformers==4.57.6 coremltools==9.0 numpy<2.3
Usage: .build/skim-venv/bin/python scripts/export-skim.py /path/to/scim-adapted
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import numpy as np
import torch
import coremltools as ct
from transformers import AutoModelForTokenClassification, AutoTokenizer

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("checkpoint", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
out = root / "Models" / "Skim"
out.mkdir(parents=True, exist_ok=True)
torch.set_num_threads(4)
model = AutoModelForTokenClassification.from_pretrained(args.checkpoint, local_files_only=True, attn_implementation="eager").eval()
assert list(model.config.id2label.values()) == ["background", "method", "objective", "other", "result"]
tokenizer = AutoTokenizer.from_pretrained(args.checkpoint, local_files_only=True)

# BERT's FP32 minimum attention-mask constant overflows FP16 on the GPU, producing
# 0 * -infinity = NaN for unmasked tokens. A finite negative mask preserves masking.
def finite_attention_mask(attention_mask, input_shape, device=None, dtype=None):
    return (1.0 - attention_mask[:, None, None, :].to(dtype or torch.float32)) * -10000.0

original_attention_mask = model.bert.get_extended_attention_mask
model.bert.get_extended_attention_mask = finite_attention_mask


class Logits(torch.nn.Module):
    def __init__(self, encoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, input_ids, attention_mask):
        return self.encoder(input_ids=input_ids, attention_mask=attention_mask).logits


wrapper = Logits(model).eval()
example = (torch.ones((1, 512), dtype=torch.int32), torch.ones((1, 512), dtype=torch.int32))
traced = torch.jit.trace(wrapper, example)
converted = ct.convert(traced, inputs=[ct.TensorType(name="input_ids", shape=(1, 512), dtype=np.int32),
                                     ct.TensorType(name="attention_mask", shape=(1, 512), dtype=np.int32)],
                       outputs=[ct.TensorType(name="logits")], minimum_deployment_target=ct.target.macOS14,
                       compute_precision=ct.precision.FLOAT16, compute_units=ct.ComputeUnit.CPU_AND_GPU)
converted.short_description = "Scim MiniLMv2-L6-H384, full-text-adapted Folio pilot; five sentence roles"
converted.license = "Apache-2.0 (upstream Scim/MiniLM); see MODEL.md"
package = root / ".build" / "AdaptedMiniLM.mlpackage"
converted.save(str(package))

# Verify native inference against the actual adapted PyTorch checkpoint before packaging.
examples = [
    ["We investigate whether a smaller model can classify scientific sentences.",
     "We train the model using labeled abstracts and full-text examples.",
     "The adapted model improves classification accuracy on the evaluation set."],
    ["Prior studies have used large transformer models for this task.",
     "Our objective is to reduce memory usage without sacrificing accuracy.",
     "We introduce a compact encoder with a five-class classification head.",
     "The experiment uses three held-out datasets and compares two baselines.",
     "The results show a reduction in prediction errors.",
     "Future work will evaluate additional domains."],
]
checks = []
for sentences in examples:
    ids, positions = [101], []
    for sentence in sentences:
        ids += tokenizer.encode(sentence, add_special_tokens=False, max_length=80, truncation=True) + [102]
        positions.append(len(ids) - 1)
    mask = [1] * len(ids) + [0] * (512 - len(ids))
    ids += [0] * (512 - len(ids))
    arrays = {"input_ids": np.array([ids], dtype=np.int32), "attention_mask": np.array([mask], dtype=np.int32)}
    model.bert.get_extended_attention_mask = original_attention_mask
    with torch.no_grad():
        reference = wrapper(*(torch.from_numpy(arrays[key]) for key in arrays)).numpy()[0, positions]
    model.bert.get_extended_attention_mask = finite_attention_mask
    actual = converted.predict(arrays)["logits"][0, positions]
    assert np.isfinite(actual).all(), "Native inference produced non-finite logits"
    assert np.array_equal(reference.argmax(-1), actual.argmax(-1)), "FP16 changed a verification label"
    probabilities = np.exp(actual - actual.max(axis=1, keepdims=True))
    probabilities /= probabilities.sum(axis=1, keepdims=True)
    checks.append({"max_logit_error": float(np.max(np.abs(reference - actual))),
                   "sentences": sentences,
                   "token_ids": [tokenizer.encode(s, add_special_tokens=False, max_length=80, truncation=True) for s in sentences],
                   "scores": probabilities.max(axis=1).tolist(),
                   "labels": actual.argmax(-1).tolist()})

compiled = Path(ct.models.utils.compile_model(str(package)))
destination = out / "AdaptedMiniLM.mlmodelc"
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(compiled, destination)
shutil.copyfile(args.checkpoint / "vocab.txt", out / "vocab.txt")
manifest = {"model": "scim-adapted", "precision": "float16", "labels": list(model.config.id2label.values()),
            "checkpoint_sha256": hashlib.sha256((args.checkpoint / "model.safetensors").read_bytes()).hexdigest(),
            "verification": checks}
(out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
print("Compiled model bytes:", sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()))
