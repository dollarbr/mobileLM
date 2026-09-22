import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../services/app_log_service.dart';
import '../services/hive_service.dart';
import 'settings_controller.dart';

class CloudProviderInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool requiresKeyForList;
  final bool supportsFetch;

  const CloudProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.requiresKeyForList = true,
    this.supportsFetch = true,
  });
}

class CloudModelController extends GetxController {
  final HiveService _hive = Get.find<HiveService>();
  final SettingsController _settings = Get.find<SettingsController>();

  static const _cachePrefix = 'cloud_model_cache_';
  static const _cacheTimePrefix = 'cloud_model_cache_time_';
  static const _defaultModelsByProvider = <String, List<String>>{
    'openrouter': [
      'openai/gpt-4o-mini',
      'openai/gpt-4o',
      'openai/gpt-4o',
      'google/gemini-2.5-flash',
      'deepseek/deepseek-chat',
      'meta-llama/llama-3.1-8b-instruct',
    ],
    'openai': [
      'gpt-5.2',
      'gpt-5.1',
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4o',
      'gpt-4o-mini',
    ],
    'deepseek': [
      'deepseek-v4-flash',
      'deepseek-v4-pro',
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    'google': [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
    'nvidia': [
      'meta/llama-3.1-8b-instruct',
      'meta/llama-3.1-70b-instruct',
      'meta/llama-3.3-70b-instruct',
      'mistralai/mixtral-8x7b-instruct-v0.1',
      'nvidia/llama-3.1-nemotron-70b-instruct',
    ],
  };

  final providers = const [
    CloudProviderInfo(
      id: 'openrouter',
      name: 'OpenRouter',
      description: 'Free model list · OpenAI compatible',
      icon: Icons.hub_outlined,
    ),
    CloudProviderInfo(
      id: 'openai',
      name: 'OpenAI',
      description: 'Native OpenAI chat models',
      icon: Icons.auto_awesome,
    ),
    CloudProviderInfo(
      id: 'deepseek',
      name: 'DeepSeek',
      description: 'OpenAI compatible V4 models',
      icon: Icons.psychology_alt_outlined,
    ),
    CloudProviderInfo(
      id: 'google',
      name: 'Google Gemini',
      description: 'Gemini native API models',
      icon: Icons.diamond_outlined,
    ),
    CloudProviderInfo(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      description: 'OpenAI compatible hosted NIM models',
      icon: Icons.memory_outlined,
    ),
    CloudProviderInfo(
      id: 'custom',
      name: 'Custom API',
      description: 'Manual OpenAI-compatible endpoint',
      icon: Icons.tune,
      supportsFetch: false,
    ),
  ];

  final modelsByProvider = <String, List<String>>{}.obs;
  final fetchedAtByProvider = <String, DateTime>{}.obs;
  final isLoadingProvider = <String, bool>{}.obs;
  final errorByProvider = <String, String>{}.obs;
  final searchByProvider = <String, String>{}.obs;
  final freeFirstByProvider = <String, bool>{}.obs;
  final modelTagsByProvider = <String, Map<String, List<String>>>{}.obs;
  final contextWindowByProvider = <String, Map<String, int>>{}.obs;
  final capabilitiesByProvider = <String, Map<String, List<String>>>{}.obs;
  final customProviderError = ''.obs;

  final customNameController = TextEditingController();
  final customBaseUrlController = TextEditingController();
  final customApiKeyController = TextEditingController();
  final customModelController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    if (!providers.any((provider) => provider.id == activeProvider)) {
      _settings.setCloudProvider('openrouter');
    }
    for (final provider in providers) {
      _loadCachedModels(provider.id);
      ensureDefaultModels(provider.id);
    }
    _syncCustomControllers();
  }

  @override
  void onClose() {
    customNameController.dispose();
    customBaseUrlController.dispose();
    customApiKeyController.dispose();
    customModelController.dispose();
    super.onClose();
  }

  String get activeProvider => _settings.cloudProvider.value;

  String activeModelFor(String provider) {
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterModel.value;
      case 'deepseek':
        return _settings.deepSeekModel.value;
      case 'google':
        return _settings.googleModel.value;
      case 'nvidia':
        return _settings.nvidiaModel.value;
      case 'custom':
        return _settings.customCloudModel.value;
      default:
        return _settings.openaiModel.value;
    }
  }

  String apiKeyFor(String provider) {
    switch (provider) {
      case 'openrouter':
        return _settings.openRouterKey.value;
      case 'deepseek':
        return _settings.deepSeekKey.value;
      case 'google':
        return _settings.googleKey.value;
      case 'nvidia':
        return _settings.nvidiaKey.value;
      case 'custom':
        return _settings.customCloudKey.value;
      default:
        return _settings.openaiKey.value;
    }
  }

  TextEditingController apiKeyControllerFor(String provider) {
    return _settings.apiKeyControllerFor(provider);
  }

  bool isConfigured(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudModel.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  String statusLabel(String provider) {
    return isConfigured(provider) ? 'Connected' : 'Needs Key';
  }

  List<String> filteredModelsFor(String provider) {
    final query = (searchByProvider[provider] ?? '').toLowerCase().trim();
    final active = activeModelFor(provider);
    final source = [...(modelsByProvider[provider] ?? const <String>[])];
    if (active.isNotEmpty && !source.contains(active)) {
      source.insert(0, active);
    }
    final filtered = query.isEmpty
        ? source
        : source.where((id) => id.toLowerCase().contains(query)).toList();
    final freeFirst = freeFirstByProvider[provider] == true;
    filtered.sort((a, b) {
      if (a == active) return -1;
      if (b == active) return 1;
      if (freeFirst) {
        final aFree = isFreeModel(provider, a);
        final bFree = isFreeModel(provider, b);
        if (aFree != bFree) return aFree ? -1 : 1;
      }
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return filtered;
  }

  String fetchedLabel(String provider) {
    final fetchedAt = fetchedAtByProvider[provider];
    if (fetchedAt == null &&
        (modelsByProvider[provider] ?? const <String>[]).isNotEmpty) {
      return 'Built-in list';
    }
    if (fetchedAt == null) return 'Not fetched yet';
    final diff = DateTime.now().difference(fetchedAt);
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inHours < 1) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  List<String> modelTagsFor(String provider, String modelId) {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (provider == 'nvidia') return const ['NIM'];
    return modelTagsByProvider[provider]?[normalized] ??
        modelTagsByProvider[provider]?[modelId] ??
        const <String>[];
  }

  /// Returns the auto-detected context window size in tokens, or null if unknown.
  int? contextWindowFor(String provider, String modelId) {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    return contextWindowByProvider[provider]?[normalized] ??
        contextWindowByProvider[provider]?[modelId];
  }

  /// Returns capabilities (vision, tools) or empty list.
  List<String> capabilitiesFor(String provider, String modelId) {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    if (provider == 'nvidia') return const [];
    return capabilitiesByProvider[provider]?[normalized] ??
        capabilitiesByProvider[provider]?[modelId] ??
        const <String>[];
  }

  /// Returns a safe maxTokens value: the smaller of [requested] and the
  /// auto-detected context window, with a minimum of 256.
  int effectiveMaxTokens(String provider, String modelId, int requested) {
    final ctx = contextWindowFor(provider, modelId);
    if (ctx == null) return requested;
    // Keep at least 25% of context for response, minimum 256 tokens
    final clamped = (ctx * 0.25).toInt().clamp(256, requested);
    return clamped < requested ? clamped : requested;
  }

  bool isFreeModel(String provider, String modelId) {
    return modelTagsFor(provider, modelId).contains('FREE') ||
        modelId.toLowerCase().contains(':free');
  }

  int freeModelCountFor(String provider) {
    return (modelsByProvider[provider] ?? const <String>[])
        .where((id) => isFreeModel(provider, id))
        .length;
  }

  void toggleFreeFirst(String provider) {
    freeFirstByProvider[provider] = !(freeFirstByProvider[provider] ?? false);
  }

  Future<void> saveApiKey(String provider, String value) async {
    await _settings.setApiKey(provider, value);
  }

  void ensureDefaultModels(String provider) {
    final defaults = _defaultModelsByProvider[provider];
    if (defaults == null || defaults.isEmpty) return;

    final existing = modelsByProvider[provider] ?? const <String>[];
    if (existing.isNotEmpty) return;

    modelsByProvider[provider] = [...defaults];
  }

  bool canFetchModels(String provider) {
    if (provider == 'custom') return false;
    return apiKeyFor(provider).isNotEmpty;
  }

  bool canSelectModel(String provider) {
    if (provider == 'custom') {
      return _settings.customCloudBaseUrl.value.isNotEmpty &&
          _settings.customCloudKey.value.isNotEmpty;
    }
    return apiKeyFor(provider).isNotEmpty;
  }

  Future<void> selectModel(
    String provider,
    String modelId, {
    bool showSnackbar = true,
  }) async {
    final normalized =
        provider == 'google' ? modelId.replaceFirst('models/', '') : modelId;
    await _settings.setCloudProvider(provider);
    await _settings.setCloudModel(provider, normalized);
    await _settings.setInferenceMode('cloud');
    if (!showSnackbar) return;
    Get.snackbar('Cloud Model Active', '$provider · $normalized',
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> saveCustomProvider() async {
    final validationError = validateCustomProvider();
    if (validationError != null) {
      customProviderError.value = validationError;
      return;
    }
    customProviderError.value = '';
    await _settings.setCustomCloudConfig(
      name: customNameController.text,
      baseUrl: customBaseUrlController.text,
      apiKey: customApiKeyController.text,
      model: customModelController.text,
    );
    await selectModel(
      'custom',
      _settings.customCloudModel.value,
      showSnackbar: false,
    );
  }

  Future<void> clearCustomProvider() async {
    await _settings.clearCustomCloudConfig();
    customProviderError.value = '';
    _syncCustomControllers();
  }

  List<Map<String, String>> get customProfiles => _settings.customCloudProfiles;

  int get customProfileIndex => _settings.customCloudProfileIndex.value;

  Future<void> selectCustomProfile(int index) async {
    await _settings.selectCustomCloudProfile(index);
    _syncCustomControllers();
    customProviderError.value = '';
  }

  void beginNewCustomProfile() {
    _settings.beginNewCustomCloudProfile();
    _syncCustomControllers();
    customProviderError.value = '';
  }

  String? validateCustomProvider() {
    final baseUrl = customBaseUrlController.text.trim();
    final apiKey = customApiKeyController.text.trim();
    final model = customModelController.text.trim();

    if (baseUrl.isEmpty) return 'Base URL is required.';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return 'Enter a valid OpenAI-compatible base URL.';
    }
    if (apiKey.isEmpty) return 'API key is required.';
    if (model.isEmpty) return 'Model ID is required.';
    return null;
  }

  Future<void> refreshModels(String provider) async {
    if (provider == 'custom') return;

    if (apiKeyFor(provider).isEmpty) {
      errorByProvider.remove(provider);
      return;
    }

    isLoadingProvider[provider] = true;
    errorByProvider.remove(provider);

    try {
      final response = await _requestModelList(provider);
      if (response.statusCode != 200) {
        final detail = '${response.statusCode}: ${_shortBody(response.body)}';
        errorByProvider[provider] = detail;
        Get.find<AppLogService>().warning(
          'Model list request failed for $provider',
          details: detail,
        );
        return;
      }

      final ids = _parseModelIds(provider, response.body);
      modelsByProvider[provider] = ids;
      modelTagsByProvider[provider] = _parseModelTags(provider, response.body);
      contextWindowByProvider[provider] = _parseContextWindows(provider, response.body);
      capabilitiesByProvider[provider] = _parseCapabilities(provider, response.body);
      final fetchedAt = DateTime.now();
      fetchedAtByProvider[provider] = fetchedAt;
      await _hive.setSetting('$_cachePrefix$provider', ids);
      await _hive.setSetting(
          '$_cacheTimePrefix$provider', fetchedAt.toIso8601String());
    } catch (e) {
      errorByProvider[provider] = '$e';
      Get.find<AppLogService>().warning(
        'Model list request failed for $provider',
        details: e,
      );
    } finally {
      isLoadingProvider[provider] = false;
    }
  }

  Future<http.Response> _requestModelList(String provider) {
    switch (provider) {
      case 'openrouter':
        return http.get(
          Uri.parse('${AppConstants.openRouterEndpoint}/models'),
          headers: {'Authorization': 'Bearer ${apiKeyFor(provider)}'},
        );
      case 'deepseek':
        return http.get(
          Uri.parse('${AppConstants.deepSeekEndpoint}/models'),
          headers: {'Authorization': 'Bearer ${apiKeyFor(provider)}'},
        );
      case 'google':
        return http.get(Uri.parse(
            '${AppConstants.googleEndpoint}?key=${apiKeyFor(provider)}'));
      case 'nvidia':
        return http.get(
          Uri.parse('${AppConstants.nvidiaEndpoint}/models'),
          headers: {'Authorization': 'Bearer ${apiKeyFor(provider)}'},
        );
      default:
        return http.get(
          Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer ${apiKeyFor(provider)}'},
        );
    }
  }

  List<String> _parseModelIds(String provider, String body) {
    final data = jsonDecode(body);
    if (provider == 'google') {
      final raw = data['models'] as List? ?? [];
      return raw
          .map((model) => model is Map ? model['name']?.toString() : null)
          .whereType<String>()
          .toSet()
          .toList();
    }

    final raw = data['data'] as List? ?? [];
    return raw
        .map((model) => model is Map ? model['id']?.toString() : null)
        .whereType<String>()
        .toSet()
        .toList();
  }

  Map<String, List<String>> _parseModelTags(String provider, String body) {
    if (provider != 'openrouter') return const {};

    final data = jsonDecode(body);
    final raw = data['data'] as List? ?? [];
    final tags = <String, List<String>>{};

    for (final model in raw) {
      if (model is! Map) continue;
      final id = model['id']?.toString();
      if (id == null || id.isEmpty) continue;

      final pricing = model['pricing'];
      final isFreeId = id.toLowerCase().contains(':free');
      final isFreePrice = pricing is Map && _isZeroOpenRouterPricing(pricing);
      if (isFreeId || isFreePrice) {
        tags[id] = const ['FREE'];
      }
    }

    return tags;
  }

  /// Parse context window sizes from API responses.
  /// Returns a map of model ID → context length in tokens.
  Map<String, int> _parseContextWindows(String provider, String body) {
    final data = jsonDecode(body);
    final result = <String, int>{};

    switch (provider) {
      case 'openrouter':
        // OpenRouter: {data: [{id, context_length, ...}]}
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          final ctx = m['context_length'] as int?;
          if (id != null && ctx != null && ctx > 0) result[id] = ctx;
        }
        break;

      case 'deepseek':
        // DeepSeek: {data: [{id, context_length, ...}]}
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          final ctx = m['context_length'] as int?;
          if (id != null && ctx != null && ctx > 0) result[id] = ctx;
        }
        break;

      case 'nvidia':
        // NVIDIA NIM: {data: [{id, context_length, ...}]}
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          final ctx = m['context_length'] as int? ?? m['contextWindow'] as int?;
          if (id != null && ctx != null && ctx > 0) result[id] = ctx;
        }
        break;

      case 'google':
        // Google: {models: [{name, supportedGenerationMethods, ...}]}
        final raw = data['models'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final name = m['name']?.toString();
          if (name == null) continue;
          final id = name.replaceFirst('models/', '');
          // Google returns approximate context in displayName or description
          final methods = m['supportedGenerationMethods'] as List? ?? [];
          final hasGenerateContent = methods.contains('generateContent');
          if (!hasGenerateContent) continue;
          final desc = (m['description'] ?? '').toString().toLowerCase();
          final disp = (m['displayName'] ?? '').toString().toLowerCase();
          // Infer context from model family
          int? ctx;
          if (id.contains('gemini-2.5-pro') || id.contains('gemini-2.5-flash')) {
            ctx = 1000000;
          } else if (id.contains('gemini-2.0-flash') || id.contains('gemini-1.5-flash')) {
            ctx = 1000000;
          } else if (id.contains('gemini-1.5-pro')) {
            ctx = 1000000;
          } else if (id.contains('gemini-exp')) {
            ctx = 1000000;
          }
          if (ctx != null) result[id] = ctx;
        }
        break;

      default:
        // OpenAI / generic: {data: [{id, context_window, ...}]}
        // Try common field names
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          final ctx = m['context_window'] as int? ?? m['contextLength'] as int?;
          if (id != null && ctx != null && ctx > 0) result[id] = ctx;
        }
        break;
    }

    return result;
  }

  /// Parse capabilities (vision, tools/function-calling) from API responses.
  Map<String, List<String>> _parseCapabilities(String provider, String body) {
    final data = jsonDecode(body);
    final result = <String, List<String>>{};

    switch (provider) {
      case 'openrouter':
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          if (id == null) continue;
          final caps = <String>[];
          final capMap = m['capabilities'] as Map? ?? {};
          if (capMap['vision'] == true || id.toLowerCase().contains('vision') ||
              id.toLowerCase().contains('flash') || id.toLowerCase().contains('glm-4v')) {
            caps.add('vision');
          }
          if (capMap['function_calling'] == true || capMap['tools'] == true ||
              id.toLowerCase().contains('tool') || id.toLowerCase().contains('function')) {
            caps.add('tools');
          }
          if (caps.isNotEmpty) result[id] = caps;
        }
        break;

      case 'deepseek':
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          if (id == null) continue;
          final caps = <String>[];
          final properties = m['properties'] as Map? ?? {};
          final abilities = properties['abilities'] as List? ?? [];
          for (final a in abilities) {
            if (a.toString().toLowerCase().contains('vision') ||
                a.toString().toLowerCase().contains('image')) {
              if (!caps.contains('vision')) caps.add('vision');
            }
            if (a.toString().toLowerCase().contains('function') ||
                a.toString().toLowerCase().contains('tool')) {
              if (!caps.contains('tools')) caps.add('tools');
            }
          }
          // DeepSeek V4 supports vision; R1 is reasoning-only
          if (id.toLowerCase().contains('v4') || id.toLowerCase().contains('chat')) {
            if (!caps.contains('vision')) caps.add('vision');
          }
          if (caps.isNotEmpty) result[id] = caps;
        }
        break;

      case 'google':
        final raw = data['models'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final name = m['name']?.toString();
          if (name == null) continue;
          final id = name.replaceFirst('models/', '');
          final methods = m['supportedGenerationMethods'] as List? ?? [];
          final hasGenerateContent = methods.contains('generateContent');
          final hasCountTokens = methods.contains('countTokens');
          if (!hasGenerateContent) continue;
          final caps = <String>[];
          // Gemini models support vision if they can generate content with inline_data
          if (id.contains('flash') || id.contains('pro') || id.contains('exp')) {
            caps.add('vision');
          }
          // Tool use is available on most modern Gemini models
          if (id.contains('flash') || id.contains('pro') || id.contains('2.5')) {
            if (!caps.contains('tools')) caps.add('tools');
          }
          if (caps.isNotEmpty) result[id] = caps;
        }
        break;

      case 'nvidia':
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          if (id == null) continue;
          final caps = <String>[];
          final props = m['properties'] as Map? ?? {};
          final abilities = props['abilities'] as List? ?? [];
          for (final a in abilities) {
            final aStr = a.toString().toLowerCase();
            if (aStr.contains('vision') || aStr.contains('image')) {
              if (!caps.contains('vision')) caps.add('vision');
            }
            if (aStr.contains('function') || aStr.contains('tool')) {
              if (!caps.contains('tools')) caps.add('tools');
            }
          }
          if (caps.isNotEmpty) result[id] = caps;
        }
        break;

      default:
        // OpenAI: infer from model ID
        final raw = data['data'] as List? ?? [];
        for (final m in raw) {
          if (m is! Map) continue;
          final id = m['id']?.toString();
          if (id == null) continue;
          final caps = <String>[];
          final lower = id.toLowerCase();
          if (lower.contains('vision') || lower.contains('gpt-4o') || lower.contains('o1') || lower.contains('o3')) {
            caps.add('vision');
          }
          if (lower.contains('gpt-4') || lower.contains('gpt-3.5') || lower.contains('o1') || lower.contains('o3')) {
            if (!caps.contains('tools')) caps.add('tools');
          }
          if (caps.isNotEmpty) result[id] = caps;
        }
        break;
    }

    return result;
  }

  bool _isZeroOpenRouterPricing(Map pricing) {
    final prompt = _pricingValue(pricing['prompt']);
    final completion = _pricingValue(pricing['completion']);
    final request = _pricingValue(pricing['request']);
    return prompt == 0 && completion == 0 && (request == null || request == 0);
  }

  double? _pricingValue(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  void _loadCachedModels(String provider) {
    final raw = _hive.getSetting<List>('$_cachePrefix$provider');
    if (raw != null) {
      modelsByProvider[provider] = raw.whereType<String>().toList();
    }
    final rawTime = _hive.getSetting<String>('$_cacheTimePrefix$provider');
    if (rawTime != null) {
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) fetchedAtByProvider[provider] = parsed;
    }
  }

  void _syncCustomControllers() {
    customNameController.text = _settings.customCloudName.value;
    customBaseUrlController.text = _settings.customCloudBaseUrl.value;
    customApiKeyController.text = _settings.customCloudKey.value;
    customModelController.text = _settings.customCloudModel.value;
  }

  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 280) return compact;
    return '${compact.substring(0, 280)}...';
  }
}
