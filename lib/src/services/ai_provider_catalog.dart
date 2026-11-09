/// Providers shown in Me → AI Mode. Listing a provider does not promise
/// unlimited free API use or an already wired inference integration.
class AiProvider {
  const AiProvider({required this.id, required this.name,
    required this.subtitle, required this.keyPage,
    this.freeTier = false, this.needsAccountId = false});

  final String id;
  final String name;
  final String subtitle;
  final String keyPage;
  final bool freeTier;
  final bool needsAccountId;
}

abstract final class AiProviderCatalog {
  static const providers = <AiProvider>[
    AiProvider(id: 'gemini', name: 'Google AI Studio (Gemini)',
      subtitle: 'Gemini models · limited free tier',
      keyPage: 'https://aistudio.google.com/apikey', freeTier: true),
    AiProvider(id: 'groq', name: 'Groq Cloud',
      subtitle: 'Fast text and document-model inference · free tier',
      keyPage: 'https://console.groq.com/keys', freeTier: true),
    AiProvider(id: 'openrouter', name: 'OpenRouter',
      subtitle: 'Multiple AI model providers · limited free models',
      keyPage: 'https://openrouter.ai/settings/keys', freeTier: true),
    AiProvider(id: 'cloudflare', name: 'Cloudflare Workers AI',
      subtitle: 'Hosted AI models · free daily allocation',
      keyPage: 'https://dash.cloudflare.com/', freeTier: true,
      needsAccountId: true),
    AiProvider(id: 'huggingface', name: 'Hugging Face',
      subtitle: 'Inference Providers · small trial credits',
      keyPage: 'https://huggingface.co/settings/tokens', freeTier: true),
    AiProvider(id: 'mistral', name: 'Mistral AI',
      subtitle: 'Text, vision and document models · plan limits apply',
      keyPage: 'https://console.mistral.ai/api-keys'),
    AiProvider(id: 'deepseek', name: 'DeepSeek',
      subtitle: 'Text and reasoning APIs · pricing varies',
      keyPage: 'https://platform.deepseek.com/api_keys'),
    AiProvider(id: 'cohere', name: 'Cohere',
      subtitle: 'Language, embedding and reranking APIs',
      keyPage: 'https://dashboard.cohere.com/api-keys'),
    AiProvider(id: 'openai', name: 'OpenAI',
      subtitle: 'Text, vision and multimodal APIs · billing may apply',
      keyPage: 'https://platform.openai.com/api-keys'),
    AiProvider(id: 'anthropic', name: 'Anthropic (Claude)',
      subtitle: 'Document and language analysis · billing may apply',
      keyPage: 'https://console.anthropic.com/settings/keys'),
    AiProvider(id: 'xai', name: 'xAI (Grok)',
      subtitle: 'Grok API models · billing may apply',
      keyPage: 'https://console.x.ai/'),
    AiProvider(id: 'together', name: 'Together AI',
      subtitle: 'Hosted open models · pricing varies',
      keyPage: 'https://api.together.ai/settings/api-keys'),
  ];

  static AiProvider? byId(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}
