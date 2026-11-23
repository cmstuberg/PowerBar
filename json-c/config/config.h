/* json-c config.h for Mac OS X 10.4+ on 32-bit PowerPC (MacOSX10.4u.sdk, gcc-4.0).
 * Written by hand from cmake/config.h.in (json-c 0.19): CMake isn't part of our
 * toolchain. Every HAVE_* below was checked against the 10.4u SDK headers and its
 * libSystem stubs, so the result runs on Tiger as well as Leopard.
 * Same for every slice (g3/g4/g5): all are ILP32 big-endian. */

/* Disabled on purpose: */
/* ENABLE_RDRAND: x86 only. */
/* ENABLE_THREADING / HAVE_ATOMIC_BUILTINS: gcc-4.0 has no __sync builtins. */
/* HAVE___THREAD: no compiler TLS on Darwin before 10.7. */
/* HAVE_GETRANDOM: Linux only; <sys/random.h> on Darwin is unrelated. */

#define HAVE_DLFCN_H 1
/* no <endian.h> on Darwin */
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYSLOG_H 1
#define HAVE_SYS_CDEFS_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
/* <xlocale.h> + uselocale/duplocale/newlocale are exported by 10.4's libSystem */
#define HAVE_XLOCALE_H 1

#define HAVE_ARC4RANDOM 1
#define HAVE_DECL_INFINITY 1
#define HAVE_DECL_ISINF 1
#define HAVE_DECL_ISNAN 1
#define HAVE_DECL_NAN 1
#define HAVE_OPEN 1
#define HAVE_REALLOC 1
#define HAVE_SETLOCALE 1
#define HAVE_SNPRINTF 1
#define HAVE_STRCASECMP 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRNCASECMP 1
#define HAVE_USELOCALE 1
#define HAVE_DUPLOCALE 1
#define HAVE_VASPRINTF 1
#define HAVE_VPRINTF 1
#define HAVE_VSNPRINTF 1
#define HAVE_VSYSLOG 1
#define HAVE_GETRUSAGE 1
#define HAVE_STRTOLL 1
#define HAVE_STRTOULL 1

#define JSON_C_HAVE_INTTYPES_H 1

#define PACKAGE "json-c"
#define PACKAGE_BUGREPORT "json-c@googlegroups.com"
#define PACKAGE_NAME "json-c"
#define PACKAGE_STRING "json-c 0.19.0"
#define PACKAGE_TARNAME "json-c"
#define PACKAGE_URL "https://github.com/json-c/json-c"
#define PACKAGE_VERSION "0.19.0"

#define SIZEOF_INT 4
#define SIZEOF_INT64_T 8
#define SIZEOF_LONG 4
#define SIZEOF_LONG_LONG 8
#define SIZEOF_SIZE_T 4
#define SIZEOF_SSIZE_T 4

#define STDC_HEADERS 1
#define VERSION "0.19.0"
