/* SPDX-License-Identifier: MIT
 * Compile once with -DFAKE_VA -shared -fPIC and once without it, linked to
 * the fake library. The executable must fail without the synchronization
 * shim and pass with LD_PRELOAD=<wsl-vaapi-serialize.so>.
 */
#define _DEFAULT_SOURCE
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>
#include <va/va.h>

#ifdef FAKE_VA
static atomic_int active, overlaps;
int test_overlaps(void) { return atomic_load(&overlaps); }
VAStatus vaEndPicture(VADisplay d, VAContextID c)
{
    (void)d; (void)c;
    if (atomic_fetch_add(&active, 1)) atomic_fetch_add(&overlaps, 1);
    usleep(1000);
    atomic_fetch_sub(&active, 1);
    return VA_STATUS_ERROR_OPERATION_FAILED;
}
VAStatus vaSyncSurface(VADisplay d, VASurfaceID s)
{
    /* Exercises recursive interposition as well as the other API entry. */
    return vaEndPicture(d, s);
}
#else
extern int test_overlaps(void);
static void *worker(void *arg)
{
    for (int i = 0; i < 25; ++i) {
        VAStatus s = arg ? vaEndPicture(NULL, 0) : vaSyncSurface(NULL, 0);
        if (s != VA_STATUS_ERROR_OPERATION_FAILED) return (void *)1;
    }
    return NULL;
}
int main(void)
{
    pthread_t threads[8];
    for (int i = 0; i < 8; ++i)
        if (pthread_create(&threads[i], NULL, worker, (void *)(long)(i % 2))) return 2;
    for (int i = 0; i < 8; ++i) {
        void *result;
        if (pthread_join(threads[i], &result) || result) return 3;
    }
    int overlaps = test_overlaps();
    printf("Concurrent VA resource accesses: %d\n", overlaps);
    return overlaps ? 1 : 0;
}
#endif
