#include <helper_cuda.h>

#define cutilCheckMsg(a) getLastCudaError(a)
#define cutGetMaxGflopsDeviceId() gpuGetMaxGflopsDeviceId()

#define MIN(a,b) (a) < (b) ? (a) : (b)
