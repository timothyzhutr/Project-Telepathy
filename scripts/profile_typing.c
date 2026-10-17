// Temporary, opt-in diagnostic tool; not linked into the IME or its worker.
// Records process counters and device-wide driver GPU utilization, never text.
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <time.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>

static volatile sig_atomic_t stopped = 0;
static double tick_nanoseconds = 1;
static void stop(int signal_number) { (void)signal_number; stopped = 1; }
static double seconds(clockid_t clock) {
  struct timespec value;
  clock_gettime(clock, &value);
  return value.tv_sec + value.tv_nsec / 1e9;
}
typedef struct { uint64_t cpu; double footprint_mb; int valid; } sample;
static sample process(pid_t pid) {
  struct rusage_info_v4 info = {0};
  if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&info) != 0) return (sample){0};
  return (sample){info.ri_user_time + info.ri_system_time, info.ri_phys_footprint / 1048576.0, 1};
}
static double utilization(CFDictionaryRef values, CFStringRef key) {
  if (!values) return -1;
  CFTypeRef value = CFDictionaryGetValue(values, key);
  double number;
  if (!value || CFGetTypeID(value) != CFNumberGetTypeID() || !CFNumberGetValue(value, kCFNumberDoubleType, &number)) return -1;
  return number;
}
static double cpu(sample before, sample after, double dt) {
  if (!before.valid || !after.valid || after.cpu < before.cpu || dt <= 0) return -1;
  // proc_pid_rusage reports Mach absolute-time ticks, not nanoseconds.
  return (after.cpu - before.cpu) * tick_nanoseconds / (dt * 1e9) * 100;
}
static void field(FILE *out, double value) {
  if (value >= 0) fprintf(out, "%.3f", value);
  fputc(',', out);
}
int main(int argc, char **argv) {
  if (argc != 6) {
    fprintf(stderr, "Usage: profile-typing NATIVE_PID WORKER_PID SECONDS INTERVAL_MS OUTPUT.csv\n");
    return 2;
  }
  pid_t native = (pid_t)strtol(argv[1], NULL, 10), worker = (pid_t)strtol(argv[2], NULL, 10);
  double duration = strtod(argv[3], NULL), interval = strtod(argv[4], NULL) / 1000;
  if (native <= 0 || worker <= 0 || duration <= 0 || duration > 3600 || interval < 0.01 || interval > 1) return 2;
  mach_timebase_info_data_t timebase;
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 1;
  tick_nanoseconds = (double)timebase.numer / timebase.denom;
  FILE *out = fopen(argv[5], "wx");
  if (!out) { perror("profile output"); return 1; }
  signal(SIGINT, stop); signal(SIGTERM, stop);
  io_service_t gpu = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"));
  fprintf(out, "unix_s,elapsed_ms,native_pid,worker_pid,native_cpu_one_core_pct,worker_cpu_one_core_pct,native_footprint_mb,worker_footprint_mb,gpu_device_driver_pct,gpu_renderer_driver_pct,sampler_cpu_one_core_pct,interval_ms\n");
  sample old_native = process(native), old_worker = process(worker), old_self = process(getpid());
  double started = seconds(CLOCK_MONOTONIC), previous = started, next = started + interval, gpu_next = started;
  double device = -1, renderer = -1;
  unsigned rows = 0;
  fprintf(stderr, "Recording CPU every %.0f ms and device-wide GPU driver counters every 100 ms for %.0f seconds. PID %d.\n", interval * 1000, duration, getpid());
  while (!stopped && seconds(CLOCK_MONOTONIC) - started < duration) {
    double remaining = next - seconds(CLOCK_MONOTONIC);
    if (remaining > 0) {
      struct timespec delay = {(time_t)remaining, (long)((remaining - (time_t)remaining) * 1e9)};
      while (nanosleep(&delay, &delay) != 0 && errno == EINTR && !stopped) {}
    }
    if (stopped) break;
    double now = seconds(CLOCK_MONOTONIC), dt = now - previous;
    sample current_native = process(native), current_worker = process(worker), current_self = process(getpid());
    if (gpu && now >= gpu_next) {
      CFTypeRef values = IORegistryEntryCreateCFProperty(gpu, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
      if (values && CFGetTypeID(values) == CFDictionaryGetTypeID()) {
        device = utilization((CFDictionaryRef)values, CFSTR("Device Utilization %"));
        renderer = utilization((CFDictionaryRef)values, CFSTR("Renderer Utilization %"));
      } else { device = renderer = -1; }
      if (values) CFRelease(values);
      gpu_next = now + 0.1;
    }
    fprintf(out, "%.6f,%.3f,%d,%d,", seconds(CLOCK_REALTIME), (now - started) * 1000, native, worker);
    field(out, cpu(old_native, current_native, dt)); field(out, cpu(old_worker, current_worker, dt));
    field(out, current_native.valid ? current_native.footprint_mb : -1);
    field(out, current_worker.valid ? current_worker.footprint_mb : -1);
    field(out, device); field(out, renderer); field(out, cpu(old_self, current_self, dt));
    fprintf(out, "%.3f\n", dt * 1000);
    if (++rows % 20 == 0) fflush(out);
    old_native = current_native; old_worker = current_worker; old_self = current_self; previous = now;
    next += interval;
    if (next <= now) next = now + interval;
    if (!current_native.valid || !current_worker.valid) {
      fprintf(stderr, "A target process stopped; ending this trace rather than sampling a replacement PID.\n");
      break;
    }
  }
  if (gpu) IOObjectRelease(gpu);
  fclose(out);
  fprintf(stderr, "Stopped after %u samples.\n", rows);
  return 0;
}
