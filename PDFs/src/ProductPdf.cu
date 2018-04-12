/*****************************************************************************/
// Author: Xuefeng Ding <xuefeng.ding.physics@gmail.com>
// Insitute: Gran Sasso Science Institute, L'Aquila, 67100, Italy
// Date: 2018 April 7th
// Version: v1.0
// Description: GooStats, a statistical analysis toolkit that runs on GPU.
//
// All rights reserved. 2018 copyrighted.
/*****************************************************************************/
#include "ProductPdf.h"
#include <utility>
#include "SumPdf.h"
extern MEM_CONSTANT fptype* dev_componentWorkSpace[100];
extern DEVICE_VECTOR<fptype>* componentWorkSpace[100];

EXEC_TARGET fptype device_ProductPdfsExtSimple (fptype* evt, fptype* p, unsigned int* indices) { 
  const int cIndex = RO_CACHE(indices[1]); 
  const fptype npe_val = evt[RO_CACHE(indices[2 + RO_CACHE(indices[0])])]; 
  const fptype npe_lo = RO_CACHE(functorConstants[cIndex]);
  const fptype npe_step = RO_CACHE(functorConstants[cIndex+1]);
  const int npe_bin = (int) FLOOR((npe_val-npe_lo)/npe_step); // no problem with FLOOR: start from 0.5, which corresponse to bin=0
  const int Ncomps = RO_CACHE(indices[2]); 
  fptype ret = 1;
  for (int par = 0; par < Ncomps; ++par) {
    const int workSpaceIndex = RO_CACHE(indices[par+3]);
    const fptype curr = RO_CACHE(dev_componentWorkSpace[workSpaceIndex][npe_bin]);
    ret *= curr; // normalization is always 1
//if(THREADIDX==0)
//    printf("x npe %.1lf npebin %d ret %.10lf w %.10lf wk %d cur %.10lf\n",npe_val,npe_bin,ret,0,workSpaceIndex,curr);
  }
//if(THREADIDX==0)
//    printf("x size %d wid1 %d wid2 %d\n",
//RO_CACHE(indices[-1+3]),
//RO_CACHE(indices[0+3]),
//RO_CACHE(indices[1+3]));
//  ret *= RO_CACHE(functorConstants[cIndex+2]); // exposure
  
  return ret; 
}

MEM_DEVICE device_function_ptr ptr_to_ProductPdfsExtSimple = device_ProductPdfsExtSimple; 

ProductPdf::ProductPdf (std::string n, const std::vector<PdfBase*> &comps,Variable *npe)
  : GooPdf(npe, n) 
{
  set_startstep(0);
  register_components(comps,npe->numbins);
  GET_FUNCTION_ADDR(ptr_to_ProductPdfsExtSimple);
  initialise(pindices); 
}
void ProductPdf::set_startstep(fptype norm) {
  Variable *npe = *(observables.begin());
  pindices.push_back(registerConstants(3));
  fptype host_iConsts[3];
  host_iConsts[0] = npe->lowerlimit;
  host_iConsts[1] = (npe->upperlimit-npe->lowerlimit)/npe->numbins;
  host_iConsts[2] = norm;
  MEMCPY_TO_SYMBOL(functorConstants, host_iConsts, 3*sizeof(fptype), cIndex*sizeof(fptype), cudaMemcpyHostToDevice);  // cIndex is a member derived from PdfBase and is set inside registerConstants method

  gooMalloc((void**) &dev_iConsts, 3*sizeof(fptype)); 
  host_iConsts[0] = npe->lowerlimit;
  host_iConsts[1] = npe->upperlimit;
  host_iConsts[2] = npe->numbins;
  MEMCPY(dev_iConsts, host_iConsts, 3*sizeof(fptype), cudaMemcpyHostToDevice); 
}
void ProductPdf::register_components(const std::vector<PdfBase*> &comps,int N) {
  components = comps;
  pindices.push_back(components.size());
  for (unsigned int w = 0; w < components.size(); ++w) {
    PdfBase *pdf = components.at(w);
    assert(pdf);
    const int workSpaceIndex = SumPdf::registerFunc(components.at(w));
    assert(workSpaceIndex<100);
    componentWorkSpace[workSpaceIndex] = new DEVICE_VECTOR<fptype>(N);
    fptype *dev_address = thrust::raw_pointer_cast(componentWorkSpace[workSpaceIndex]->data());
    MEMCPY_TO_SYMBOL(dev_componentWorkSpace, &dev_address, sizeof(fptype*), workSpaceIndex*sizeof(fptype*), cudaMemcpyHostToDevice); 
    pindices.push_back(workSpaceIndex);
  }
}

__host__ fptype ProductPdf::normalise () const {
  host_normalisation[parameters] = 1.0; 
  thrust::counting_iterator<int> binIndex(0); 

  Variable *npe = *(observables.begin());
  m_updated = false;
  for (unsigned int i = 0; i < components.size(); ++i) {
    GooPdf *component = dynamic_cast<GooPdf*>(components.at(i));
    if (component->parametersChanged()) {
      m_updated = true;
      component->normalise();  // this is needed for the GeneralConvolution
      thrust::constant_iterator<fptype*> startendstep(dev_iConsts); // 3*fptype lo, hi and step for npe
      thrust::constant_iterator<int> eventSize(1); // 1: only npe
      BinnedMetricTaker modalor(component, getMetricPointer("ptr_to_Eval")); 
      const int workSpaceIndex = SumPdf::registerFunc(components.at(i));
      thrust::transform(thrust::make_zip_iterator(thrust::make_tuple(binIndex, eventSize, startendstep)),
          thrust::make_zip_iterator(thrust::make_tuple(binIndex + npe->numbins, eventSize, startendstep)),
          componentWorkSpace[workSpaceIndex]->begin(),
          modalor);
      SYNCH(); 
      component->storeParameters();
    }
  }
  return 1; 
}
