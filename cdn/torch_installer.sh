#!/bin/bash

git clone https://github.com/torch/distro.git ~/torch --recursive
cd ~/torch
export TORCH_NVCC_FLAGS="-D__CUDA_NO_HALF_OPERATORS__"
module load cuda/9.0
module load cudnn/7-cuda-9.0
./install.sh
