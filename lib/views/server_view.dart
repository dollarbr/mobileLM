import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../controllers/model_controller.dart';
import '../controllers/server_controller.dart';
import '../core/colors.dart';
import '../core/constants.dart';
import '../utils/server_auth.dart';
import 'system_one_console.dart';
import '../services/text_interpolation.dart';

class ServerView extends GetView<ServerController> {
  const ServerView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFB9F53E) : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
        title: Text('server'.tr,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: Obx(() {
        final isRunning = controller.isRunning.value;
        final hasKey = controller.apiKey.value.trim().isNotEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Status
            _groupedCard(isDark, children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            color: (isRunning
                                    ? AppColors.success
                                    : Theme.of(context).hintColor)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(
                            isRunning ? Icons.dns_rounded : Icons.dns_outlined,
                            size: 20,
                            color: isRunning
                                ? AppColors.success
                                : Theme.of(context).hintColor)),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              (isRunning
                                      ? 'sc_title_running'
                                      : 'sc_title_stopped')
                                  .tr,
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                              isRunning
                                  ? controller.serverStatus.value
                                  : 'sc_subtitle_stopped'.tr,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(context).hintColor)),
                        ])),
                    Switch(
                        value: isRunning,
                        onChanged: controller.isStarting.value
                            ? null
                            : (v) => controller.toggleServer(v)),
                  ])),
            ]),
            const SizedBox(height: 12),

            // Model
            _groupedCard(isDark, children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                            color: (controller.hasLocalModel
                                    ? AppColors.success
                                    : AppColors.warning)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(7)),
                        child: Icon(
                            controller.hasLocalModel
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 16,
                            color: controller.hasLocalModel
                                ? AppColors.success
                                : AppColors.warning)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(controller.modelName,
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                              // Not "requires a loaded model" any more, because
                              // it does not. The server starts with nothing
                              // loaded precisely so a client can load one over
                              // it, and the endpoints that need a model refuse
                              // on their own with a 400 that names the file to
                              // POST. Saying "requires" here would contradict
                              // the toggle two rows up that now works.
                              controller.hasLocalModel
                                  ? 'sv_local_model_ready'.tr
                                  : 'sv_no_model_loaded'.tr,
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Theme.of(context).hintColor)),
                        ])),
                  ])),
            ]),
            const SizedBox(height: 12),

            // Port
            _sectionLabel(context, 'sv_port_label'),
            _groupedCard(isDark, children: [
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            preencher('sc_port_hint', {'p': AppConstants.defaultServerPort.toString()}),
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF8E8E93))),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: controller.portCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      signed: false),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null && n > 0 && n < 65536) {
                                  controller.serverPort.value = n;
                                }
                              },
                              onSubmitted: (_) => controller.saveSettings(),
                              // Not `const`: the hint has to come from the constant
                              // so it cannot go stale, and calling `.toString()` on
                              // it is not a constant expression. A hardcoded '8080'
                              // here was the third copy of the default, in the one
                              // place a person actually reads it.
                              decoration: InputDecoration(
                                labelText: 'sv_port_field'.tr,
                                hintText:
                                    AppConstants.defaultServerPort.toString(),
                                prefixIcon:
                                    const Icon(Icons.portrait, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () {
                              controller.portCtrl.text =
                                  AppConstants.defaultServerPort.toString();
                              controller.serverPort.value =
                                  AppConstants.defaultServerPort;
                            },
                            child: Text('reset'.tr),
                          ),
                        ]),
                      ])),
            ]),
            const SizedBox(height: 12),

            // Security
            _sectionLabel(context, 'sc_section_security'),
            _groupedCard(isDark, children: [
              _switchTile(isDark,
                  title: 'sv_require_api_key'.tr,
                  subtitle: 'sv_authorization_bearer'.tr,
                  value: controller.useApiKey.value,
                  onChanged: (v) => _onRequireKeyChanged(context, v)),
              Divider(
                  height: 0.5,
                  indent: 16,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06)),
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                      controller: controller.apiKeyCtrl,
                      onChanged: (v) => controller.apiKey.value = v,
                      onSubmitted: (_) => controller.saveSettings(),
                      decoration: InputDecoration(
                          labelText: 'mv_api_key'.tr,
                          // Not "Optional" any more. The requirement is on by
                          // default and a key is generated at first boot, so
                          // the field is never empty in practice — and a hint
                          // saying it is optional is what makes a person
                          // believe the field can be left alone.
                          hintText: controller.apiKey.value.isEmpty
                              ? 'Generated on first run'
                              : 'sv_required_by_toggle'.tr),
                    )),
                    const SizedBox(width: 6),
                    IconButton(
                        tooltip: 'sc_generate_key'.tr,
                        onPressed: controller.generateApiKey,
                        icon: Icon(Icons.auto_awesome_rounded,
                            size: 20, color: accent)),
                    IconButton(
                        tooltip: 'sc_copy'.tr,
                        onPressed: hasKey
                            ? () => controller.copyText(
                                controller.apiKey.value, 'mv_api_key'.tr)
                            : null,
                        icon: Icon(Icons.copy_outlined,
                            size: 18, color: Theme.of(context).hintColor)),
                  ])),
            ]),
            const SizedBox(height: 12),

            if (isRunning) ...[
              _sectionLabel(context, 'sc_section_endpoints'),
              _groupedCard(isDark, children: [
                Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _urlRow(context, isDark, 'local'.tr,
                              controller.localUrl.value),
                          const SizedBox(height: 8),
                          // A `Wrap`, not a `Row`. Three of the overflows this
                          // repo has paid for were a `Row` of buttons with
                          // nothing limiting it, and these two are exactly that
                          // shape: an icon plus an English label each, side by
                          // side, at 2× text on a 360 dp screen.
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                  onPressed: controller.localUrl.value == null
                                      ? null
                                      : () => _testHealth(
                                          controller.localUrl.value!),
                                  icon: const Icon(Icons.wifi, size: 16),
                                  label: Text('test_local'.tr)),
                              // The System One window lives here rather than on
                              // the model cards, and that is a decision about
                              // where the knowledge is. A GGUF answers with a
                              // letter or with logits, and which one is only
                              // visible after a load — so offering a "decision"
                              // button on 36 chat model cards would be 36 wrong
                              // buttons. Here, a model is loaded and its shape is
                              // a fact.
                              OutlinedButton.icon(
                                onPressed: () => _openSystemOne(context),
                                icon: const Icon(Icons.rule, size: 16),
                                label: Text('soc_system_one_test_b'.tr),
                              ),
                            ],
                          ),
                        ])),
              ]),
              const SizedBox(height: 12),
              _sectionLabel(context, 'sc_section_examples'),
              _usageExamples(context, isDark, controller),
            ],

            if (controller.lastError.value != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(controller.lastError.value!,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: AppColors.error))),
                    ]),
              ),
            ],
          ],
        );
      }),
    );
  }

  // ── Usage examples, for the model that is actually loaded ──
  //
  // The three encoder endpoints did not exist when this screen was written, and
  // the static list offered `/v1/chat/completions` to everyone. For a BERT that
  // is a request that cannot work — there is no LM head — so the example was
  // teaching the wrong thing to everyone and the right thing to no one.
  //
  // The examples are chosen by `modelRole` rather than printed all at once: a
  // generation model has no `/v1/embeddings` to show, and a reranker has no
  // `/v1/chat/completions`. The role comes from the encoder surface the native
  // side reports, not from the file name, because the file name is how the
  // bge-small with a size-1 classification head got called a classifier.
  Widget _usageExamples(
      BuildContext context, bool isDark, ServerController controller) {
    final base = controller.baseUrl;
    final model = controller.inference.loadedModelName.value;
    final role = controller.modelRole;
    final maxTokens = controller.encoder.value?.maxInputTokens ?? 0;

    final blocks = <Widget>[];

    // Com o servidor no ar e nenhum modelo carregado, `role` é null e a tela
    // mostrava um `curl /v1/chat/completions` que só volta 400. Agora o servidor
    // sobe sem modelo justamente para isto, então os primeiros exemplos são os
    // de gestão — que são os que funcionam.
    if (model.isEmpty) {
      blocks.add(_codeBlock(context, isDark, 'sc_what_is_here'.tr,
          'curl $base/v1/models/local${_authHeader()}'));
      blocks.add(_codeBlock(
          context,
          isDark,
          'sc_load_downloaded'.tr,
          'curl $base/v1/models/load \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n'
              '  -d \'{"filename":"LFM2.5-230M-Q4_0.gguf","accept_risk":true}\'\n\n'
              '# 202, then poll /v1/models/local until its state is "loaded".\n'
              '# accept_risk stands for the tap on "Load" in the app; the file and\n'
              '# memory checks still run and can still refuse. LiteRT (.litertlm)\n'
              '# loads the same way.'));
      blocks.add(_codeBlock(
          context,
          isDark,
          'sc_download_catalogue'.tr,
          'curl $base/v1/models/download \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n'
              '  -d \'{"filename":"<filename>"}\'\n\n'
              '# Progress shows up as state "downloading" on /v1/models/local.'));
    } else if (role == null) {
      blocks.add(_codeBlock(context, isDark, 'List models',
          'curl $base/v1/models${_authHeader()}'));
      blocks.add(_codeBlock(context, isDark, 'Chat completion',
          'curl $base/v1/chat/completions \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"model":"$model","messages":[{"role":"user","content":"Hello"}]}\''));
      blocks.add(_codeBlock(context, isDark, 'Python SDK',
          'from openai import OpenAI\n\nclient = OpenAI(\n    base_url="$base/v1",\n    api_key="${controller.useApiKey.value ? controller.apiKey.value : "not-needed"}"\n)\n\nresponse = client.chat.completions.create(\n    model="$model",\n    messages=[{"role": "user", "content": "Hello"}],\n)\nprint(response.choices[0].message.content)'));
    } else if (role == 'embedding') {
      final dims = controller.encoder.value?.outputLength ?? 0;
      blocks.add(_codeBlock(context, isDark, 'List models',
          'curl $base/v1/models${_authHeader()}'));
      blocks.add(_codeBlock(
          context,
          isDark,
          'Embeddings — one vector per input',
          'curl $base/v1/embeddings \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"model":"$model","input":["first text","second text"]}\'\n\n# returns data[].embedding, one array of $dims floats each, L2-normalised\n# (measured on the Edge 60: norm 1.000000, so cosine is a plain dot product)'));
      blocks.add(_codeBlock(context, isDark, 'Python SDK',
          'from openai import OpenAI\n\nclient = OpenAI(\n    base_url="$base/v1",\n    api_key="${controller.useApiKey.value ? controller.apiKey.value : "not-needed"}"\n)\n\nvectors = client.embeddings.create(\n    model="$model",\n    input=["first text", "second text"],\n).data\nprint(len(vectors[0].embedding), "dimensions")'));
    } else if (role == 'reranker') {
      blocks.add(_codeBlock(context, isDark, 'List models',
          'curl $base/v1/models${_authHeader()}'));
      blocks.add(_codeBlock(
          context,
          isDark,
          'Rerank — score a query against documents',
          'curl $base/v1/rerank \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"query":"how much storage does the map cache use",'
              '"documents":["The cache holds about 340 MB.","Olive oil is pressed cold."]}\'\n\n# results come back sorted, best first, as {index, relevance_score}\n# the score is a logit: measured on the Edge 60, -0.37 to +2.19, so sigmoid\n# it and the high 0.9s are the ones that mean something'));
      if (maxTokens > 0) {
        blocks.add(_codeBlock(
            context,
            isDark,
            'Limit',
            preencher('sc_encoder_limit_example', {'n': maxTokens.toString()})));
      }
      blocks.add(_codeBlock(
          context,
          isDark,
          'Python SDK',
          'from openai import OpenAI\n\nclient = OpenAI(\n    base_url="$base/v1",\n    api_key="${controller.useApiKey.value ? controller.apiKey.value : "not-needed"}"\n)\n\n'
              '# the rerank shape follows Cohere and Jina, not OpenAI\n'
              'resp = client.post(\n    "/rerank",\n    json={\n        "model": "$model",\n        "query": "how much storage does the map cache use",\n'
              '        "documents": ["The cache holds about 340 MB.", "Olive oil is pressed cold."],\n    },\n)\n'
              'for hit in resp.json()["results"]:\n    print(hit["relevance_score"], hit["index"])'));
    } else {
      final labels = controller.encoder.value?.labels ?? const <String>[];
      blocks.add(_codeBlock(context, isDark, 'List models',
          'curl $base/v1/models${_authHeader()}'));
      blocks.add(_codeBlock(
          context,
          isDark,
          'Classify — one score per label',
          'curl $base/v1/classify \\\n  -H "Content-Type: application/json"${_authHeader()} \\\n  -d \'{"input":"some text","labels":${_dartList(labels)}}\'\n\n'
              '# this app\'s own shape: there is no standard one.\n'
              '# labels come from the GGUF; a model with one label is a reranker, not a classifier.'));
    }

    return _groupedCard(isDark, children: [
      Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: blocks)),
    ]);
  }

  String _dartList(List<String> items) =>
      items.isEmpty ? '[]' : '[${items.map((e) => '"$e"').join(",")}]';

  // ── Helpers ──

  Widget _groupedCard(bool isDark, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// Recebe uma **chave** e traduz aqui, como o `_sectionLabel` de
  /// `settings_view.dart`.
  ///
  /// **Os dois helpers tinham o mesmo nome e contratos diferentes**, e era o que
  /// quebrava: o de settings fazia `Text(chave.tr.toUpperCase())` e o daqui
  /// `Text(title)` — ou seja, um recebia chave e o outro texto pronto. Passar
  /// `'sc_section_security'` para o segundo renderizava **o identificador na
  /// tela**, e nada reclamava: o `l10n_keys_test` só afirma que a chave existe
  /// no mapa, e ela existia. A tela do servidor mostrou `sc_section_security`
  /// onde deveria mostrar `SEGURANÇA`, e foi o `dump` do A72 que disse.
  ///
  /// Receber a chave é o contrato que não se esquece: quem escreve
  /// `_sectionLabel(context, …)` não tem como passar texto sem `.tr` por acidente,
  /// porque a tradução está dentro do helper.
  Widget _sectionLabel(BuildContext context, String chave) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6, top: 8),
      child: Text(chave.tr,
          style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Theme.of(context).hintColor)),
    );
  }

  /// Turning the key OFF asks first, and the question is the specific one.
  ///
  /// Not a generic "are you sure". The consequences of no key are concrete and
  /// the user cannot see them from a switch: the server listens on all
  /// interfaces, so it is reachable from every device on the same network, and
  /// since the model-management endpoints landed, an unauthenticated caller can
  /// write gigabytes to the phone, unload whatever is loaded under every other
  /// client, and list what is on it. That is a different risk from the one this
  /// setting was invented for, which is why a switch that used to be a harmless
  /// toggle now needs a confirmation that says all of it.
  ///
  /// The switch is left where it was if the person backs out — the tap is
  /// undone, not just ignored, because a switch that snaps back on its own
  /// after a cancel reads as the app having changed its mind.
  Future<void> _onRequireKeyChanged(BuildContext context, bool required) async {
    final controller = Get.find<ServerController>();

    if (required) {
      // Turning it ON is never questioned. It cannot lose anyone access.
      if (!controller.apiKey.value.trim().isEmpty) {
        controller.useApiKey.value = true;
        await controller.saveSettings();
        return;
      }
      // No key to require yet, which is the one case where the switch is
      // asking for something that does not exist. Generate rather than
      // refusing: an empty requirement is the state this whole change exists to
      // remove.
      await controller.generateApiKey();
      return;
    }

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('sv_turn_off_key'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'sv_anyone_on_network'.tr,
              style: GoogleFonts.inter(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 14),
            // Named, because "it gets worse" is not something a person can
            // weigh. Each line is an endpoint that exists today.
            _consequence(context, 'sc_download_here'.tr,
                'POST /v1/models/download — writes gigabytes here'),
            _consequence(
                context,
                'sc_unload'.tr,
                'POST /v1/models/load, /v1/models/unload — every other client '
                    'on the network changes model too'),
            _consequence(context, 'sc_list_here'.tr,
                'GET /v1/models/local — model names, sizes, what is loaded'),
            _consequence(
                context,
                'sc_use_for_inference'.tr,
                '/v1/chat/completions and /v1/completions — spends battery and '
                    'data'),
            const SizedBox(height: 12),
            Text(
              'sv_turning_back_on'.tr,
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Theme.of(context).hintColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('sv_keep_key'.tr),
          ),
          // The safe answer is the default action, so Enter and the visual
          // order both point at not doing it.
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('sc_turn_off_anyway'.tr),
          ),
        ],
      ),
    );

    if (go != true) {
      // Put the switch back where it was.
      controller.useApiKey.value = true;
      return;
    }
    controller.useApiKey.value = false;
    await controller.saveSettings();
    Get.snackbar(
      'sv_api_key_off'.tr,
      'sc_network_warning'.tr,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 6),
    );
  }

  /// One line of the consequences list: what, and the endpoint that makes it
  /// true. The endpoint is the part that stops this being a warning the user
  /// has to take on faith.
  Widget _consequence(BuildContext context, String what, String how) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.arrow_right_rounded,
                size: 15, color: AppColors.error),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what,
                    style: GoogleFonts.inter(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(how,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(bool isDark,
      {required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.inter(fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF8E8E93)
                      : const Color(0xFF8E8E93)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _urlRow(BuildContext context, bool isDark, String label, String? url) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 54,
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(
              child: SelectableText(url ?? 'sv_not_available'.tr,
                  maxLines: 1,
                  style: GoogleFonts.firaCode(
                      fontSize: 12, color: Theme.of(context).hintColor))),
          IconButton(
              tooltip: 'sc_copy'.tr,
              onPressed: url == null
                  ? null
                  : () => controller.copyText(url, '$label URL'),
              icon: Icon(Icons.copy_outlined,
                  size: 16, color: Theme.of(context).hintColor)),
        ]));
  }

  Widget _codeBlock(
      BuildContext context, bool isDark, String title, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600))),
          IconButton(
              tooltip: 'sc_copy'.tr,
              onPressed: () => controller.copyText(code, title),
              icon: Icon(Icons.copy_outlined,
                  size: 16, color: Theme.of(context).hintColor)),
        ]),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(code,
                style: GoogleFonts.firaCode(
                    fontSize: 12, color: Theme.of(context).hintColor))),
      ]),
    );
  }

  String _authHeader() {
    if (controller.useApiKey.value && controller.apiKey.value.isNotEmpty) {
      return ' \\\n  -H "Authorization: Bearer ${controller.apiKey.value}"';
    }
    return '';
  }

  Future<void> _testHealth(String baseUrl) async {
    try {
      final r = await http
          .get(Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/health'))
          .timeout(const Duration(seconds: 8));
      Get.snackbar('Health check', 'Status ${r.statusCode}');
    } catch (e) {
      Get.snackbar('sv_health_failed'.tr, '$e');
    }
  }

  /// Open the System One window for whatever is loaded.
  ///
  /// The shape is deliberately left [SystemOneShape.unknown] and the window is
  /// left to ask the server what it is. Deciding here from the filename would be
  /// the exact mistake the whole feature is built to avoid: a name is not an
  /// architecture, and `tev1-Q8_0.gguf` is not a decision model because of the
  /// "tev1".
  void _openSystemOne(BuildContext context) {
    final embedders = <String>[];
    if (Get.isRegistered<ModelController>()) {
      embedders.addAll(
        Get.find<ModelController>().curatedEmbedders.map((m) => m.filename),
      );
    }
    Get.to(() => SystemOneConsole(
          onClose: () => Get.back(),
          // The server's own address, and its own auth — including the API key
          // when the user turned it on. Every in-app client that skipped this
          // header made its console read "server not running" against a server
          // that was running, and nothing else on screen changed.
          baseUrl: controller.baseUrl,
          authHeaders: localApiHeaders(
            useApiKey: controller.useApiKey.value,
            apiKey: controller.apiKey.value,
          ),
          embedders: embedders,
        ));
  }
}
