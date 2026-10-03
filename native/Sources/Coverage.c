#include "Coverage.h"
#include <stdlib.h>
#include <string.h>
int tp_commit_composition(RimeSessionId s) { return rime_get_api()->commit_composition(s); }
void tp_candidate_ends(RimeSessionId s, int count, int *ends) {
  if (count < 0 || count > 12) return;
  RimeApi *api = rime_get_api();
  for (int i = 0; i < count; ++i) ends[i] = -1;
  RIME_STRUCT(RimeContext, initial);
  if (!api->get_context(s, &initial)) return;
  char *words[12] = {0};
  RimeCandidateListIterator it = {0};
  int n = 0;
  if (api->candidate_list_begin(s, &it)) {
    while (n < count && api->candidate_list_next(&it))
      words[n++] = strdup(it.candidate.text ? it.candidate.text : "");
    api->candidate_list_end(&it);
  }
  count = n;
  if (count && RIME_API_AVAILABLE(api, highlight_candidate)) {
    int original = initial.menu.page_no * initial.menu.page_size + initial.menu.highlighted_candidate_index;
    const char *native_input = api->get_input(s);
    char *input = strdup(native_input ? native_input : "");
    if (!input) { for (int i = 0; i < count; ++i) free(words[i]); api->free_context(&initial); return; }
    size_t input_len = strlen(input);
    for (int i = 0; i < count; ++i) {
      api->highlight_candidate(s, (size_t)i);
      RIME_STRUCT(RimeContext, probe);
      if (!api->get_context(s, &probe)) continue;
      const char *preedit = probe.composition.preedit;
      int end = probe.composition.sel_end;
      int highlighted = probe.menu.highlighted_candidate_index;
      if (preedit && end >= 0 && (size_t)end <= strlen(preedit) &&
          highlighted >= 0 && highlighted < probe.menu.num_candidates &&
          probe.menu.candidates[highlighted].text &&
          words[i] && !strcmp(probe.menu.candidates[highlighted].text, words[i])) {
        const char *suffix = preedit + end;
        size_t suffix_len = strlen(suffix);
        if (input && suffix_len <= input_len && !strcmp(input + input_len - suffix_len, suffix))
          ends[i] = (int)(input_len - suffix_len);
      }
      api->free_context(&probe);
    }
    api->highlight_candidate(s, (size_t)original);
    native_input = api->get_input(s);
    if (!native_input || strcmp(input, native_input))
      for (int i = 0; i < count; ++i) ends[i] = -1;
    free(input);
  }
  for (int i = 0; i < count; ++i) free(words[i]);
  api->free_context(&initial);
}
