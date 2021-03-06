#include "goofit/PdfBase.h"
#include "goofit/FitManager.h"
#include "goofit/PDFs/GooPdf.h"
#include <cstdio> 
#include <cassert> 
#include <limits> 
#include <typeinfo> 
#include <set>
#include "goofit/Variable.h"

using namespace std; 

#if MINUIT_VERSION == 1
#include "FitManagerMinuit1.cc"
#elif MINUIT_VERSION == 2
#include "FitManagerMinuit2.cc"
#else 
#include "FitManagerMinuit3.cc"
#endif 
