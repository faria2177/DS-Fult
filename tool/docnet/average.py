"""Average several DocNet checkpoints (stochastic weight averaging).

    python3 tool/docnet/average.py out.pt docnet.pt.e10 ... docnet.pt.e16

The shipped model is the average of epochs 10–16 of a 16-epoch run on
14 000 images (make_data.py seeds 21 and 22).
"""
import sys

import torch

states = [torch.load(p, map_location='cpu') for p in sys.argv[2:]]
avg = {k: (sum(s[k].float() for s in states) / len(states)).to(states[0][k].dtype)
       for k in states[0]}
torch.save(avg, sys.argv[1])
print('averaged', len(states), 'checkpoints into', sys.argv[1])
