#Python T-SNE GPU

A work still in early progress.

Implementation of T-SNE for Python using the GPU.

`nvcc --compile -I /usr/local/cuda/samples/common/inc tsne_p.cu -o tsne_p.o --compiler-options -fPIC`

`nvcc main.cpp`
