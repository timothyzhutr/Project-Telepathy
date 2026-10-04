/* Evaluation-only bridge: fresh non-learning sessions, native first-page order.
   Compile with native/Sources/Coverage.c to use production candidate coverage. */
#include <rime_api.h>
#include "Coverage.h"
#include <stdlib.h>
#include <string.h>
static RimeApi *api;
static RimeContext context;
static int has_context;
static int ends[12];
int tp_open(const char *shared, const char *user) {
  api = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared; traits.user_data_dir = user;
  traits.app_name = "rime.telepathy.rankerevaluation";
  traits.log_dir = user; traits.min_log_level = 3;
  api->setup(&traits); api->initialize(&traits);
  RimeSessionId session = api->create_session();
  int ok = session && api->select_schema(session, "wanxiang");
  if (session) api->destroy_session(session);
  return ok;
}
int tp_lookup(const char *input) {
  if (has_context) { api->free_context(&context); has_context = 0; }
  RimeSessionId session = api->create_session();
  if (!session || !api->select_schema(session, "wanxiang")) return 0;
  api->set_option(session, "ascii_mode", False);
  api->set_option(session, "zh_simp", True);
  api->set_option(session, "context_reorder", False);
  api->set_option(session, "s2t", False);
  api->set_option(session, "s2hk", False);
  api->set_option(session, "s2tw", False);
  for (const unsigned char *p = (const unsigned char *)input; *p; ++p)
    api->process_key(session, *p, 0);
  memset(&context, 0, sizeof(context)); RIME_STRUCT_INIT(RimeContext, context);
  has_context = api->get_context(session, &context);
  if (has_context) tp_candidate_ends(session, context.menu.num_candidates > 12 ? 12 : context.menu.num_candidates, ends);
  api->destroy_session(session);
  return has_context;
}
int tp_count(void) { return has_context ? context.menu.num_candidates : 0; }
const char *tp_text(int i) { return i >= 0 && i < tp_count() ? context.menu.candidates[i].text : NULL; }
int tp_end(int i) { return i >= 0 && i < 12 ? ends[i] : -1; }
const char *tp_version(void) { return api->get_version(); }
void tp_close(void) {
  if (has_context) { api->free_context(&context); has_context = 0; }
  if (api) { api->finalize(); api = NULL; }
}
