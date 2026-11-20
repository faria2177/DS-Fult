"""Export a trained DocNet to ncnn (param + bin) with pnnx.

    python3 tool/docnet/export.py docnet.pt OUT_DIR
"""
import os
import shutil
import subprocess
import sys
import tempfile

import torch

sys.path.insert(0, os.path.dirname(__file__))
from train import DocNet  # noqa: E402


def main():
    weights, out_dir = sys.argv[1], sys.argv[2]
    model = DocNet()
    model.load_state_dict(torch.load(weights, map_location='cpu'))
    model.eval()
    work = tempfile.mkdtemp()
    traced = os.path.join(work, 'docnet.pt')
    torch.jit.trace(model, torch.rand(1, 3, 160, 160)).save(traced)
    subprocess.run(['pnnx', traced, 'inputshape=[1,3,160,160]', 'fp16=0'],
                   cwd=work, check=True, stdout=subprocess.DEVNULL)
    os.makedirs(out_dir, exist_ok=True)
    shutil.copy(os.path.join(work, 'docnet.ncnn.param'),
                os.path.join(out_dir, 'docnet.param'))
    shutil.copy(os.path.join(work, 'docnet.ncnn.bin'),
                os.path.join(out_dir, 'docnet.bin'))
    print('exported to', out_dir)


if __name__ == '__main__':
    main()
