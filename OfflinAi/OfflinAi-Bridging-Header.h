//
//  OfflinAi-Bridging-Header.h
//

#ifndef OfflinAi_Bridging_Header_h
#define OfflinAi_Bridging_Header_h

// Original Metal shader types
#include "ShaderTypes.h"

// OfflinAi C Interpreter (C89/C99/C23)
#include "offlinai_cc.h"

// OfflinAi C++ Interpreter
#include "offlinai_cpp.h"

// OfflinAi Fortran Interpreter
#include "offlinai_fortran.h"

// LaTeX Engine (pdftex via lib-tex + ios_system)
#import <ios_system/ios_system.h>

// pdftex library entry point
extern int dllpdftexmain(int argc, char *argv[]);

#endif
