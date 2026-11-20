"""Train DocNet: a small U-Net that outputs the document mask.

    python3 tool/docnet/train.py data1.npz [data2.npz ...] --out docnet.pt

Input 1×3×160×160 RGB in [0, 1] (photo squashed to a square), output
1×1×80×80 logits. ~0.2 M parameters; runs in a few milliseconds on a
phone with ncnn. Only ncnn-friendly layers: Conv, ReLU, nearest upsample,
concat.
"""
import argparse
import time

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


def conv(cin, cout, stride=1):
    return nn.Sequential(
        nn.Conv2d(cin, cout, 3, stride, 1, bias=False),
        nn.BatchNorm2d(cout),
        nn.ReLU(inplace=True))


def dw(cin, cout):
    """Depthwise-separable 3×3."""
    return nn.Sequential(
        nn.Conv2d(cin, cin, 3, 1, 1, groups=cin, bias=False),
        nn.BatchNorm2d(cin),
        nn.ReLU(inplace=True),
        nn.Conv2d(cin, cout, 1, bias=False),
        nn.BatchNorm2d(cout),
        nn.ReLU(inplace=True))


class DocNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.e1 = nn.Sequential(conv(3, 16, 2), conv(16, 16))           # 80
        self.e2 = nn.Sequential(conv(16, 32, 2), dw(32, 32))            # 40
        self.e3 = nn.Sequential(conv(32, 64, 2), dw(64, 64), dw(64, 64))  # 20
        self.e4 = nn.Sequential(conv(64, 96, 2), dw(96, 96), dw(96, 96))  # 10
        self.d3 = dw(96 + 64, 64)
        self.d2 = dw(64 + 32, 32)
        self.d1 = dw(32 + 16, 16)
        self.head = nn.Conv2d(16, 1, 1)

    def forward(self, x):
        e1 = self.e1(x)
        e2 = self.e2(e1)
        e3 = self.e3(e2)
        e4 = self.e4(e3)
        d3 = self.d3(torch.cat([F.interpolate(e4, scale_factor=2.0, mode='nearest'), e3], 1))
        d2 = self.d2(torch.cat([F.interpolate(d3, scale_factor=2.0, mode='nearest'), e2], 1))
        d1 = self.d1(torch.cat([F.interpolate(d2, scale_factor=2.0, mode='nearest'), e1], 1))
        return self.head(d1)


def augment(x, y):
    if torch.rand(1) < .5:
        x, y = x.flip(3), y.flip(3)
    if torch.rand(1) < .3:
        x, y = x.flip(2), y.flip(2)
    if torch.rand(1) < .3:
        x, y = x.transpose(2, 3), y.transpose(2, 3)
    # brightness / contrast jitter per sample
    b = x.shape[0]
    gain = torch.empty(b, 1, 1, 1).uniform_(.7, 1.25)
    bias = torch.empty(b, 1, 1, 1).uniform_(-.08, .08)
    x = (x * gain + bias).clamp(0, 1)
    # colour: random channel order, some samples greyscale
    if torch.rand(1) < .5:
        x = x[:, torch.randperm(3)]
    grey = torch.rand(b, 1, 1, 1) < .2
    x = torch.where(grey, x.mean(1, keepdim=True).expand_as(x), x)
    x = (x + torch.randn_like(x) * .02).clamp(0, 1)
    return x, y


def loss_fn(logits, y):
    bce = F.binary_cross_entropy_with_logits(logits, y)
    p = torch.sigmoid(logits)
    inter = (p * y).sum((1, 2, 3))
    dice = 1 - (2 * inter + 1) / (p.sum((1, 2, 3)) + y.sum((1, 2, 3)) + 1)
    return bce + dice.mean()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('data', nargs='+')
    ap.add_argument('--out', default='docnet.pt')
    ap.add_argument('--epochs', type=int, default=24)
    ap.add_argument('--batch', type=int, default=64)
    ap.add_argument('--init', help='start from these weights (fine-tuning)')
    ap.add_argument('--lr', type=float, default=3e-3)
    args = ap.parse_args()
    torch.set_num_threads(2)
    torch.manual_seed(0)
    xs, ys = [], []
    for path in args.data:
        d = np.load(path)
        xs.append(d['x'])
        ys.append(d['y'])
    x = torch.from_numpy(np.concatenate(xs)).permute(0, 3, 1, 2).contiguous()
    y = torch.from_numpy(np.concatenate(ys)).unsqueeze(1).contiguous()
    n_val = 300
    xv, yv = x[:n_val], y[:n_val]
    xt, yt = x[n_val:], y[n_val:]
    model = DocNet()
    if args.init:
        model.load_state_dict(torch.load(args.init, map_location='cpu'))
    print('params', sum(p.numel() for p in model.parameters()))
    opt = torch.optim.AdamW(model.parameters(), args.lr, weight_decay=1e-4)
    steps = args.epochs * (len(xt) // args.batch)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, args.lr, total_steps=steps)
    for epoch in range(args.epochs):
        model.train()
        perm = torch.randperm(len(xt))
        t0 = time.time()
        total = 0.0
        for i in range(len(xt) // args.batch):
            idx = perm[i * args.batch:(i + 1) * args.batch]
            bx = xt[idx].float() / 255
            by = yt[idx].float()
            bx, by = augment(bx, by)
            loss = loss_fn(model(bx), by)
            opt.zero_grad()
            loss.backward()
            opt.step()
            sched.step()
            total += loss.item()
        model.eval()
        with torch.no_grad():
            pv = torch.cat([model(xv[i:i + 100].float() / 255) for i in range(0, n_val, 100)]) > 0
            inter = (pv & (yv > 0)).sum((1, 2, 3)).float()
            union = (pv | (yv > 0)).sum((1, 2, 3)).float()
            miou = (inter / union.clamp(min=1)).mean().item()
        print(f'epoch {epoch + 1} loss {total / (len(xt) // args.batch):.4f} '
              f'val mIoU {miou:.4f} {time.time() - t0:.0f}s', flush=True)
        torch.save(model.state_dict(), args.out)
        torch.save(model.state_dict(), f'{args.out}.e{epoch + 1}')


if __name__ == '__main__':
    main()
