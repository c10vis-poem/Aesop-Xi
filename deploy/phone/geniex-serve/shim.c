// Thin C shim over libgeniex.so (v0.3.14 ABI, header pinned from 2026-06-25)
// so Python can drive it through ctypes with plain types only.
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "geniex.h"

static geniex_LLM* g_llm = NULL;

int shim_load(const char* model, const char* mode, int n_ctx) {
    int rc = geniex_init();
    if (rc < 0) { fprintf(stderr, "geniex_init: %s\n", geniex_get_error_message(rc)); return rc; }
    geniex_ResolveDeviceInput ri = { "llama_cpp", model, mode, 999 };
    geniex_ResolveDeviceOutput ro = {0};
    rc = geniex_resolve_device(&ri, &ro);
    if (rc < 0) { fprintf(stderr, "resolve_device: %s\n", geniex_get_error_message(rc)); return rc; }
    if (ro.warning) fprintf(stderr, "resolve_device warning: %s\n", ro.warning);
    fprintf(stderr, "device=%s ngl=%d mode=%s\n", ro.device_id ? ro.device_id : "(default)", ro.ngl, mode);

    geniex_LlmCreateInput in = {0};
    in.model_name = model;
    in.model_path = model;
    in.plugin_id = "llama_cpp";
    in.device_id = ro.device_id;
    in.config.n_ctx = n_ctx;
    in.config.n_gpu_layers = ro.ngl;
    in.config.enable_sampling = true;
    rc = geniex_llm_create(&in, &g_llm);
    if (rc < 0) fprintf(stderr, "llm_create: %s\n", geniex_get_error_message(rc));
    return rc;
}

// One stateless chat completion. Tokens stream through cb; full text in *out_text
// (free with shim_free). stats = {prompt_tokens, generated_tokens, prefill tok/s, decode tok/s}.
int shim_chat(int n, const char** roles, const char** contents, int max_tokens,
              float temperature, float top_p, int enable_thinking,
              geniex_token_callback cb, void* ud,
              char** out_text, double* stats, char* stop_reason, int stop_reason_len) {
    if (!g_llm) return -1;
    geniex_llm_reset(g_llm);

    geniex_LlmChatMessage* msgs = calloc(n, sizeof *msgs);
    for (int i = 0; i < n; i++) { msgs[i].role = roles[i]; msgs[i].content = contents[i]; }
    geniex_LlmApplyChatTemplateInput ti = { msgs, n, NULL, enable_thinking != 0, true };
    geniex_LlmApplyChatTemplateOutput to = {0};
    int rc = geniex_llm_apply_chat_template(g_llm, &ti, &to);
    free(msgs);
    if (rc < 0) { fprintf(stderr, "chat_template: %s\n", geniex_get_error_message(rc)); return rc; }

    geniex_SamplerConfig sc = {0};
    sc.temperature = temperature; sc.top_p = top_p; sc.top_k = 40; sc.min_p = 0.05f;
    sc.repetition_penalty = 1.0f; sc.seed = -1;
    geniex_GenerationConfig gc = {0};
    gc.max_tokens = max_tokens; gc.sampler_config = &sc;
    geniex_LlmGenerateInput gi = {0};
    gi.prompt_utf8 = to.formatted_text; gi.config = &gc; gi.on_token = cb; gi.user_data = ud;
    geniex_LlmGenerateOutput go = {0};
    rc = geniex_llm_generate(g_llm, &gi, &go);
    geniex_free(to.formatted_text);
    if (rc < 0) { fprintf(stderr, "generate: %s\n", geniex_get_error_message(rc)); return rc; }

    *out_text = go.full_text;
    stats[0] = (double)go.profile_data.prompt_tokens;
    stats[1] = (double)go.profile_data.generated_tokens;
    stats[2] = go.profile_data.prefill_speed;
    stats[3] = go.profile_data.decoding_speed;
    snprintf(stop_reason, stop_reason_len, "%s", go.profile_data.stop_reason ? go.profile_data.stop_reason : "");
    return 0;
}

void shim_free(void* p) { geniex_free(p); }
