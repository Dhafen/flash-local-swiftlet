#!/usr/bin/env python3
"""Experimental 150M P2P fixed-window Core ML export.

Port based on elefant-ai/open-p2p (MIT), pinned upstream a329d98cbe62119679a254d71bea6446773541bc.
No upstream training runtime or gated text encoder required for the no-instruction path.
Export is deliberately NOT an iOS integration: require checkpoint and numerical validation.
"""
import argparse
import json
from pathlib import Path
import numpy as np
import torch
from torch import nn
import torch.nn.functional as F
from torchvision.models import efficientnet_b0

REPO = "elefantai/open-p2p"
REV = "bbe1a35"
CHECKPOINT = "150M/checkpoint-step=00500000.ckpt"
D = 1024
N_KEYS, N_BUTTONS, N_ACTIONS = 4, 2, 8
VOCABS = (20, 20, 20, 20, 4, 4, 23, 17)
PREFIXES = ("key_action_embedding",) * 4 + ("mouse_button_embedding",) * 2 + ("mouse_delta_x_embedding", "mouse_delta_y_embedding")
HEADS = ("keyboard_out_logits",) * 4 + ("mouse_button_out_logits",) * 2 + ("mouse_delta_x_out_logits", "mouse_delta_y_out_logits")
STEP = 4 + N_ACTIONS

class Weights:
    def __init__(self, sd):
        self.sd = sd
        self.used = set()
    def get(self, name, shape=None):
        if name not in self.sd:
            raise KeyError(f"Missing checkpoint tensor: {name}")
        value = self.sd[name]
        if shape is not None and tuple(value.shape) != tuple(shape):
            raise ValueError(f"{name}: expected {shape}, got {tuple(value.shape)}")
        self.used.add(name)
        return value.detach().float()
    def linear(self, name, bias):
        weight = self.get(name + ".weight")
        m = nn.Linear(weight.shape[1], weight.shape[0], bias=bias)
        m.weight = nn.Parameter(weight, requires_grad=False)
        if bias:
            m.bias = nn.Parameter(self.get(name + ".bias", (weight.shape[0],)), requires_grad=False)
        return m
    def const(self, name, shape):
        return nn.Parameter(self.get(name, shape), requires_grad=False)

def rms(x, scale):
    return x * torch.rsqrt(x.square().mean(-1, keepdim=True) + 1e-5) * scale

def rotary_cache(length, head_dim):
    angles = torch.arange(length, dtype=torch.float32)[:, None] * (10000.0 ** (-torch.arange(0, head_dim, 2, dtype=torch.float32) / head_dim))[None]
    return angles.cos()[None, None], angles.sin()[None, None]

def rotary(x, co, si):
    pairs = x.reshape(x.shape[0], x.shape[1], x.shape[2], x.shape[3] // 2, 2)
    a, b = pairs[..., 0], pairs[..., 1]
    return torch.stack((a * co - b * si, b * co + a * si), -1).flatten(3)

def policy_mask(frames):
    i = torch.arange(frames * STEP)
    q, k = i[:, None], i[None, :]
    earlier = (q // STEP > k // STEP) & (k % STEP != 3)
    same = q // STEP == k // STEP
    within = ((q % STEP < 3) & (k % STEP < 3)) | ((q % STEP == 3) & (k % STEP <= 3)) | ((q % STEP > 3) & (k % STEP != 3))
    return earlier | (same & within)

class Block(nn.Module):
    def __init__(self, w, name, heads, length, mask):
        super().__init__()
        p = name + ".self_attention"
        self.h = heads
        self.d = D // heads
        self.qkv = w.linear(p + ".c_attn", False)
        self.out = w.linear(p + ".c_proj", False)
        self.qnorm = w.const(p + ".q_norm.scale", (D,))
        self.knorm = w.const(p + ".k_norm.scale", (D,))
        self.anorm = w.const(name + ".self_attention_norm.scale", (D,))
        self.fnorm = w.const(name + ".ffn_norm.scale", (D,))
        self.ff1 = w.linear(name + ".ffn.w13", False)
        self.ff2 = w.linear(name + ".ffn.w2", False)
        self.register_buffer("cos", rotary_cache(length, self.d)[0])
        self.register_buffer("sin", rotary_cache(length, self.d)[1])
        self.register_buffer("mask", mask[None, None])
        self.reference = False
    def forward(self, x):
        b, t, _ = x.shape
        q, k, v = self.qkv(rms(x, self.anorm)).split(D, dim=-1)
        q = rms(q, self.qnorm).reshape(b,t,self.h,self.d).transpose(1,2)
        k = rms(k, self.knorm).reshape(b,t,self.h,self.d).transpose(1,2)
        v = v.reshape(b,t,self.h,self.d).transpose(1,2)
        q, k = rotary(q,self.cos,self.sin), rotary(k,self.cos,self.sin)
        if self.reference:
            y = F.scaled_dot_product_attention(q,k,v,attn_mask=self.mask)
        else:
            score = (q @ k.transpose(-2,-1)) * (self.d ** -0.5)
            y = torch.softmax(score.masked_fill(~self.mask, -1e4), -1) @ v
        h = x + self.out(y.transpose(1,2).reshape(b,t,D))
        a, b = self.ff1(rms(h, self.fnorm)).chunk(2, dim=-1)
        return h + self.ff2(F.silu(a) * b)

class ActionEmbedding(nn.Module):
    def __init__(self, w):
        super().__init__()
        self.tables = nn.ModuleList([nn.Embedding.from_pretrained(w.get(p+".weight", (n,D)), freeze=True) for p,n in zip(PREFIXES,VOCABS)])
    def forward(self, actions):
        return torch.stack([emb(actions[...,i].long()) for i,emb in enumerate(self.tables)], dim=-2)

class Policy(nn.Module):
    def __init__(self, w, frames):
        super().__init__()
        self.frames = frames
        # The checkpoint can contain both aliases because the same encoder is used by the policy.
        p = "bc_transformer."
        enc = p+"image_tokenizer."
        if enc+"mlp.0.weight" not in w.sd:
            enc = "image_tokenizer."
        self.vision = efficientnet_b0(weights=None).features[:6]
        state = {k: w.get(enc+"efficientnet_preprocess."+k) for k in self.vision.state_dict()}
        self.vision.load_state_dict(state, strict=True)
        self.fc = w.linear(enc+"mlp.0", True)
        self.ln = nn.LayerNorm(D)
        self.ln.weight = w.const(enc+"mlp.1.weight",(D,))
        self.ln.bias = w.const(enc+"mlp.1.bias",(D,))
        self.imgpos = w.const(p+"img_pos_tokens",(1,1,D))
        self.text = w.const(p+"text_embedding_for_no_text_input",(1,1,D))
        self.textpos = w.const(p+"text_pos_tokens",(1,1,D))
        self.think = w.const(p+"thinking_pos_tokens",(1,1,D))
        self.out = w.const(p+"action_out_token",(1,1,D))
        self.actionpos = w.const(p+"action_pos_tokens",(1,N_ACTIONS,D))
        self.actions = ActionEmbedding(w)
        self.blocks = nn.ModuleList([Block(w,p+"_transformer.transformer_layers."+str(i),16,frames*STEP,policy_mask(frames)) for i in range(10)])
    def forward(self, frames, action_history):
        # [T,3,192,192] RGB in [0,1]; each of the T rows has eight action IDs.
        img = self.ln(self.fc(self.vision(frames).reshape(self.frames,-1))).reshape(self.frames,1,D) + self.imgpos
        act = self.actions(action_history).reshape(self.frames,N_ACTIONS,D) + self.actionpos
        x = torch.cat(((self.text+self.textpos).expand(self.frames,-1,-1),img,
                       self.think.expand(self.frames,-1,-1),self.out.expand(self.frames,-1,-1),act),1).reshape(1,self.frames*STEP,D)
        for layer in self.blocks:
            x = layer(x)
        return x[:, (self.frames-1)*STEP+3, :]

class Decoder(nn.Module):
    def __init__(self,w):
        super().__init__()
        p = "bc_transformer.action_decoder."
        self.pos = w.const(p+"pos_tokens",(N_ACTIONS+1,D))
        self.proj = w.linear(p+"input_proj",True)
        self.actions = ActionEmbedding(w)
        self.blocks = nn.ModuleList([Block(w,p+"transformer_layers."+str(i),8,N_ACTIONS+1,torch.ones(N_ACTIONS+1,N_ACTIONS+1,dtype=torch.bool).tril()) for i in range(3)])
        self.heads = nn.ModuleList([w.linear(h,True) for h in HEADS])
    def forward(self, context, prefix):
        x = torch.cat((self.proj(context).unsqueeze(1),self.actions(prefix)),dim=1)+self.pos[None]
        for layer in self.blocks:
            x = layer(x)
        rows = []
        for i,head in enumerate(self.heads):
            logits = head(x[:,i,:])
            rows.append(F.pad(logits,(0,23-VOCABS[i]),value=-1e4))
        return torch.stack(rows,dim=1)

def greedy(decoder, context, prefix):
    out = prefix.clone()
    with torch.inference_mode():
        for i in range(N_ACTIONS):
            logits = decoder(context,out)[0,i,:VOCABS[i]]
            out[0,i] = logits.argmax()
    return out

def verify_torch(model, inputs):
    with torch.inference_mode():
        for layer in model.blocks: layer.reference = True
        reference = model(*inputs)
        for layer in model.blocks: layer.reference = False
        actual = model(*inputs)
        torch.testing.assert_close(actual,reference,rtol=1e-3,atol=2e-3)
        traced = torch.jit.trace(model, inputs, check_trace=True)
        torch.testing.assert_close(traced(*inputs),reference,rtol=1e-3,atol=2e-3)
    return traced

def convert(model, inputs, names, output, out_name, ct):
    traced = verify_torch(model,inputs)
    converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
        inputs=[ct.TensorType(name=n,shape=tuple(x.shape),dtype=np.int32 if x.dtype==torch.int32 else np.float32) for n,x in zip(names,inputs)],
        outputs=[ct.TensorType(name=out_name,dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16, compute_units=ct.ComputeUnit.CPU_ONLY)
    converted.save(str(output))
    # A second real execution on macOS, no artifact on a failed check.
    native = ct.models.MLModel(str(output),compute_units=ct.ComputeUnit.CPU_ONLY)
    report = []
    for seed in (1,17):
        rng=torch.Generator().manual_seed(seed)
        sample = tuple(torch.rand(x.shape,generator=rng) if x.dtype==torch.float32 else x.clone() for x in inputs)
        with torch.inference_mode(): expected=model(*sample).numpy()
        actual=native.predict(dict(zip(names,[x.numpy() for x in sample])))[out_name]
        if not np.isfinite(actual).all():
            raise RuntimeError("Core ML returned non-finite values")
        # Ignore intentionally masked logits for relative error; verify separately.
        valid=np.abs(expected)<9999
        if not np.all(actual[~valid]<-9000): raise RuntimeError("Invalid action slots are not masked")
        mae=float(np.mean(np.abs(expected[valid]-actual[valid])))
        denominator=max(float(np.sqrt(np.mean(expected[valid]**2))),1e-6)
        nrmse=float(np.sqrt(np.mean((expected[valid]-actual[valid])**2)))/denominator
        if nrmse>0.08: raise RuntimeError(f"{out_name} Core ML deviation {nrmse}")
        report.append({"seed":seed,"mae":mae,"nrmse":nrmse})
    return report

def main():
    from huggingface_hub import hf_hub_download
    import coremltools as ct
    parser=argparse.ArgumentParser()
    parser.add_argument("out",type=Path)
    parser.add_argument("--frames",type=int,default=4,choices=(1,4,8))
    args=parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    path=hf_hub_download(REPO,CHECKPOINT,revision=REV)
    # Do not execute arbitrary pickle classes; the published checkpoint must load under weights_only.
    raw=torch.load(path,map_location="cpu",weights_only=True,mmap=True)
    w=Weights(raw["state_dict"])
    policy=Policy(w,args.frames).eval()
    decoder=Decoder(w).eval()
    # The remaining parameters may include duplicate encoder aliases or training-only heads.
    unknown=[k for k in w.sd if k not in w.used and not k.startswith(("image_tokenizer.","bc_transformer.image_tokenizer.","bc_transformer.text_embed_mlp."))]
    print("Unused checkpoint keys:",unknown[:100],flush=True)
    weights_used=sum(w.sd[k].numel() for k in w.used)
    if weights_used<100_000_000: raise RuntimeError("Unexpectedly few original parameters")
    actions=torch.zeros((args.frames,N_ACTIONS),dtype=torch.int32)
    actions[:,6]=11
    actions[:,7]=8
    frames=torch.rand((args.frames,3,192,192),generator=torch.Generator().manual_seed(13))
    context=policy(frames,actions).detach()
    prefix=actions[-1:].clone()
    print("PyTorch greedy IDs:",greedy(decoder,context,prefix).tolist(),flush=True)
    report={}
    report["policy"]=convert(policy,(frames,actions),("frames","action_history"),args.out/"policy.mlpackage","context",ct)
    report["decoder"]=convert(decoder,(context,prefix),("context","prefix"),args.out/"decoder.mlpackage","logits",ct)
    manifest={"schema":1,"upstream":REPO+"@"+REV,"weights_used":weights_used,"frames":args.frames,
              "vocab_sizes":VOCABS,"sampling":"greedy sequential","text_conditioning":False,
              "verified":"dense PyTorch SDPA vs explicit attention and Core ML CPU predictions; not original upstream end-to-end parity",
              "validation":report}
    (args.out/"manifest.json").write_text(json.dumps(manifest,indent=2))
    print(json.dumps(manifest,indent=2),flush=True)
if __name__=="__main__":
    main()
