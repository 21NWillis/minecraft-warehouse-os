#!/usr/bin/env python3
"""Train a tiny char-level neural language model (Bengio-2003 style) in pure
Python - no numpy, no torch - so it can be re-implemented byte-for-byte in Lua
and run inference on the Minecraft GPU peripheral.

Architecture:  context of B chars -> embed(d) each -> concat(B*d)
               -> Linear(B*d, H) -> tanh -> Linear(H, V) -> softmax
Exports weights + a validation trace so the Lua/Java port can be checked to
match these logits exactly.
"""
import math
import json
import random
from pathlib import Path

random.seed(1337)

HERE = Path(__file__).parent
B = 6      # context length (chars)
D = 6      # embedding dim
H = 24     # hidden units
LR = 0.2
EPOCHS = 60

# thematic corpus - repetitive/structured so a ~2k-param model learns word shape
CORPUS = (
    "the paperclip factory turns iron into paperclips. "
    "iron becomes gears, gears become machines, machines make paperclips. "
    "the factory grows. the factory optimizes. the factory never stops. "
    "more iron, more gears, more machines, more paperclips forever. "
    "the datacenter hums. the turtles craft. the cache stays warm. "
    "paperclips, paperclips, endless paperclips from the factory. "
) * 6

chars = sorted(set(CORPUS))
V = len(chars)
stoi = {c: i for i, c in enumerate(chars)}
itos = {i: c for i, c in enumerate(chars)}


def randmat(rows, cols, scale):
    return [[random.gauss(0, scale) for _ in range(cols)] for _ in range(rows)]


# parameters
E = randmat(V, D, 0.5)                       # embedding table
W1 = randmat(B * D, H, 1.0 / math.sqrt(B * D))
b1 = [0.0] * H
W2 = randmat(H, V, 1.0 / math.sqrt(H))
b2 = [0.0] * V


def tanh(x):
    if x > 20: return 1.0
    if x < -20: return -1.0
    e = math.exp(2 * x)
    return (e - 1) / (e + 1)


def forward(ctx):
    # embed + concat
    emb = []
    for c in ctx:
        emb.extend(E[c])
    # hidden = tanh(emb @ W1 + b1)
    hpre = [b1[j] + sum(emb[i] * W1[i][j] for i in range(B * D)) for j in range(H)]
    h = [tanh(v) for v in hpre]
    # logits = h @ W2 + b2
    logits = [b2[k] + sum(h[j] * W2[j][k] for j in range(H)) for k in range(V)]
    m = max(logits)
    exps = [math.exp(l - m) for l in logits]
    s = sum(exps)
    probs = [e / s for e in exps]
    return emb, h, logits, probs


# build training examples: sliding window
data = [stoi[c] for c in CORPUS]
examples = []
for i in range(len(data) - B):
    examples.append((data[i:i + B], data[i + B]))

print(f"vocab={V} params~={V*D + B*D*H + H + H*V + V} examples={len(examples)}")

for epoch in range(EPOCHS):
    random.shuffle(examples)
    total_loss = 0.0
    lr = LR * (0.5 ** (epoch / 25))
    for ctx, target in examples:
        emb, h, logits, probs = forward(ctx)
        total_loss += -math.log(probs[target] + 1e-9)
        # backward
        dlogits = probs[:]
        dlogits[target] -= 1.0
        # W2, b2
        dh = [0.0] * H
        for j in range(H):
            for k in range(V):
                dh[j] += dlogits[k] * W2[j][k]
                W2[j][k] -= lr * dlogits[k] * h[j]
        for k in range(V):
            b2[k] -= lr * dlogits[k]
        # tanh
        dhpre = [dh[j] * (1 - h[j] * h[j]) for j in range(H)]
        # W1, b1, and into embedding
        demb = [0.0] * (B * D)
        for i in range(B * D):
            for j in range(H):
                demb[i] += dhpre[j] * W1[i][j]
                W1[i][j] -= lr * dhpre[j] * emb[i]
        for j in range(H):
            b1[j] -= lr * dhpre[j]
        for bi in range(B):
            for di in range(D):
                E[ctx[bi]][di] -= lr * demb[bi * D + di]
    if epoch % 10 == 0 or epoch == EPOCHS - 1:
        print(f"epoch {epoch:3d}  loss {total_loss/len(examples):.3f}  lr {lr:.3f}")


def generate(seed, n, temp=0.8):
    ctx = [stoi.get(c, 0) for c in seed[-B:].rjust(B)][-B:]
    out = seed
    for _ in range(n):
        _, _, logits, probs = forward(ctx)
        if temp <= 0:
            nxt = max(range(V), key=lambda k: probs[k])
        else:
            scaled = [math.exp(math.log(p + 1e-9) / temp) for p in probs]
            s = sum(scaled)
            r = random.random() * s
            acc = 0.0
            nxt = V - 1
            for k in range(V):
                acc += scaled[k]
                if r <= acc:
                    nxt = k
                    break
        out += itos[nxt]
        ctx = ctx[1:] + [nxt]
    return out


print("\n--- greedy sample ---")
print(generate("the ", 120, temp=0))
print("\n--- temp 0.8 sample ---")
print(generate("iron ", 120, temp=0.8))

# export weights (compact) + a validation trace (greedy argmax path)
weights = {
    "B": B, "D": D, "H": H, "V": V,
    "chars": "".join(chars),
    "E": E, "W1": W1, "b1": b1, "W2": W2, "b2": b2,
}
(HERE / "nanolm_weights.json").write_text(json.dumps(weights))

# flat text format for cheap Lua parsing
lines = [f"{B} {D} {H} {V}", "".join(chars)]
def flat(m):
    if isinstance(m[0], list):
        return " ".join(f"{x:.6f}" for row in m for x in row)
    return " ".join(f"{x:.6f}" for x in m)
for name, m in (("E", E), ("W1", W1), ("b1", b1), ("W2", W2), ("b2", b2)):
    lines.append(flat(m))
(HERE / "nanolm_weights.txt").write_text("\n".join(lines))

# validation: greedy generation from a fixed seed + logits at each step
val_seed = "the fac"
ctx = [stoi.get(c, 0) for c in val_seed[-B:]]
trace = {"seed": val_seed, "steps": []}
gen = val_seed
for _ in range(40):
    _, _, logits, probs = forward(ctx)
    nxt = max(range(V), key=lambda k: probs[k])
    trace["steps"].append({"logits": [round(x, 5) for x in logits], "argmax": nxt})
    gen += itos[nxt]
    ctx = ctx[1:] + [nxt]
trace["greedy"] = gen
(HERE / "nanolm_val.json").write_text(json.dumps(trace))
print("\ngreedy(the fac):", gen)
print("exported nanolm_weights.txt + validation trace")
