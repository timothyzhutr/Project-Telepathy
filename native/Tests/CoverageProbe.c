#include "Coverage.h"
void tp_real_candidate_ends(RimeSessionId session, int count, int *ends);
static int probes = 0;
void tp_candidate_ends(RimeSessionId session, int count, int *ends) {
  ++probes;
  tp_real_candidate_ends(session, count, ends);
}
int tp_test_probe_count(void) { return probes; }
