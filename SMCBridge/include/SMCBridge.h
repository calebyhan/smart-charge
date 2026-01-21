#ifndef SMCBridge_h
#define SMCBridge_h

#include <IOKit/IOKitLib.h>

// SMC key types
#define SMC_KEY_SIZE 4

// Function prototypes
kern_return_t SMCOpen(io_connect_t *conn);
kern_return_t SMCClose(io_connect_t conn);
kern_return_t SMCReadKey(io_connect_t conn, const char *key, double *value);

#endif
