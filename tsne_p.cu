#include <time.h>
#include "nvmatrix.cuh"
#include "tsne_p.cuh"
#include <cuda_runtime_api.h>
#include <cuda.h>
#include <cfloat>


/* Implementation of t-SNE in CUDA (designed for Matlab).
 *
 *
 * (C) Laurens van der Maaten, 2010
 * University of California, San Diego
 *
 */
void tsne_p(float* inp_P, unsigned int N, float* mappedX, unsigned int no_dims) {

    /* Initialize some variables */
    int max_iter = 1000;
    float initial_momentum = 0.5f;
	float final_momentum = 0.8f;
    int momentum_switch_iter = 250;
    int lie_switch_iter = 100;
    float momentum = initial_momentum;    
	float eta = 500.0f;
	
    /* Fire up cublas */
    checkCudaErrors(cudaSetDevice(cutGetMaxGflopsDeviceId()));
    cublasStatus status = cublasInit();
    if(status != CUBLAS_STATUS_SUCCESS) {
        fprintf(stderr, "!!!! cublas initialization failed\n");
    }
	NVMatrix::initDeviceProps();
    NVMatrix::initRandom(time(0));

    /* Print memory information */
    size_t freeMem, totalMem;
    cuMemGetInfo(&freeMem, &totalMem);
    fprintf(stdout, "Running CUDA implementation of t-SNE...\n");
    fprintf(stdout, " - GPU memory is %d bytes (%d available).\n", totalMem, freeMem);
    fprintf(stdout, " - NOTE: This implementation does not show intermediate plots.\n");

    /* Copy data onto device, and make sure it is normalized */
    NVMatrix* Q = new NVMatrix(N, N);
    NVMatrix* P = new NVMatrix(true, inp_P, N, N);
	P->zeroDiagonal();
    Q->copyFromDevice(*P);
    P->add(Q->getTranspose());
    P->scale(1.0f / P->sum());
	P->addScalar(FLT_MIN);
	P->scale(4.0f);
	
    /* Initialize the solution */
    NVMatrix* Y = new NVMatrix(N, no_dims, false);
    Y->apply(NVMatrix::ZERO);
    Y->addGaussianNoise(0.0001f);

    /* Allocate some memory */
    NVMatrix* Qnum = new NVMatrix(N, N);
	NVMatrix* sum_Q = new NVMatrix(1, N);
	NVMatrix* sum_Y = new NVMatrix(1, N);
	NVMatrix* square_Y = new NVMatrix(N, no_dims);
	NVMatrix* dY = new NVMatrix(N, no_dims);
	NVMatrix* diffY = new NVMatrix(N, no_dims);
	NVMatrix* incY = new NVMatrix(N, no_dims);
    NVMatrix* gains = new NVMatrix(N, no_dims);
    NVMatrix* gains_update1 = new NVMatrix(N, no_dims);
	NVMatrix* gains_update2 = new NVMatrix(N, no_dims);
	incY->apply(NVMatrix::ZERO);
    gains->apply(NVMatrix::ONE);
	
    /* Perform updates */
    for(int iter = 0; iter < max_iter; iter++) {
		
		/* Create transposes, and stop early stopping */
		NVMatrix* Y_trans = &Y->getTranspose();
		NVMatrix* sum_Y_trans = &sum_Y->getTranspose();
		if(iter == lie_switch_iter) {
			P->scale(0.25f);
		}
        if(iter == momentum_switch_iter) {
            momentum = final_momentum;
        }
		
		/* Compute pairwise similarity matrix for the map */		
		square_Y->copyFromDevice(*Y);
		square_Y->apply(NVMatrix::SQUARE);
		square_Y->sum(1, *sum_Y);
		Y->rightMult(*Y_trans, -2.0f, *Qnum);
		Qnum->addVector(*sum_Y);
		Qnum->addVector(*sum_Y_trans);
		Qnum->apply(NVMatrix::STUDENT);
		Qnum->zeroDiagonal();
		Q->copyFromDevice(*Qnum);
		Q->scale(1.0f / Q->sum());
		
		/* Clean up memory */
		delete Y_trans;
		delete sum_Y_trans;
		
		/* Compute gradient */
		Q->add(*P, -1.0f, 1.0f);
		Q->eltWiseMult(*Qnum);     
		Q->sum(0, *sum_Q);
		Q->scale(-1.0f);
		Q->setDiagonal(*sum_Q);
		Q->rightMult(*Y, *dY);

        /* Update gains */
        dY->compareSigns(*incY, *gains_update1);
        gains_update1->addScalar(-1.0f); 
        gains_update1->scale(-1.0f);        
        dY->compareSigns(*incY, *gains_update2);
        gains_update2->eltWiseMult(*gains);
        gains_update2->scale(0.8f);        
        gains->addScalar(0.2f);
        gains->eltWiseMult(*gains_update1);
        gains->add(*gains_update2);
        
		/* Perform map update */
        dY->eltWiseMult(*gains);
		incY->add(*dY, momentum, -eta);
		Y->add(*incY);
		
		/* Print out progress */
		if((iter + 1) % 100 == 0) {
			Q->copyFromDevice(*Qnum);
			Q->scale(1.0f / Q->sum());
			Q->addScalar(FLT_MIN);
			P->eltWiseDivide(*Q, *Q);
			Q->apply(NVMatrix::LOG);
			Q->eltWiseMult(*P);
			Q->zeroDiagonal();
			float C = Q->sum();
			fprintf(stdout, "Iteration %d of %d: KL(P||Q) = %f\n", iter + 1, max_iter, C);
		}
	}
	
	/* Copy low-dimensional map to host */
	cudaThreadSynchronize();
	Y->getTranspose().copyToHost(mappedX, no_dims, N);
	
	/* Clean up some memory */
	delete Y;
	delete Q;
	delete Qnum;
	delete sum_Q;
	delete sum_Y;
	delete square_Y;
	delete dY;
	delete diffY;
	delete incY;
    delete gains;
    delete gains_update1;
    delete gains_update2;
	       
    /* Shut down cublas */
    NVMatrix::destroyRandom();
    status = cublasShutdown();
	if(status != CUBLAS_STATUS_SUCCESS) {
		fprintf(stderr, "!!!! error while shutting down cublas\n");
	}
	cudaThreadExit();
}


int main()
{
    printf("Hello??");
    return 0;
}
