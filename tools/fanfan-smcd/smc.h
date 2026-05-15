/*
 * Minimal Apple SMC structures/constants used by fanfan-smcd.
 * Based on the public smcFanControl-style AppleSMC user client layout.
 */

#ifndef FFAN_SMCD_SMC_H
#define FFAN_SMCD_SMC_H

#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC      2

#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_KEYINFO  9

#define DATATYPE_FLT          "flt "
#define DATATYPE_FPE2         "fpe2"

typedef struct {
    char   major;
    char   minor;
    char   build;
    char   reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version;
    UInt16 length;
    UInt32 cpuPLimit;
    UInt32 gpuPLimit;
    UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char   dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

typedef struct {
    UInt32                  key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    char                    result;
    char                    status;
    char                    data8;
    UInt32                  data32;
    SMCBytes_t              bytes;
} SMCKeyData_t;

typedef char UInt32Char_t[5];

typedef struct {
    UInt32Char_t key;
    UInt32       dataSize;
    UInt32Char_t dataType;
    SMCBytes_t   bytes;
} SMCVal_t;

#endif
