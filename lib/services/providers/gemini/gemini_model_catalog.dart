/// Curated audio capable Gemini API models. Billing eligibility is descriptive
/// metadata; it cannot be inferred from an API key or account response.
class GeminiModelOption {
  const GeminiModelOption({
    required this.id,
    required this.name,
    required this.specialized,
    required this.freeTier,
  });

  final String id;
  final String name;
  final bool specialized;
  final bool freeTier;

  String get billingLabel => freeTier ? 'Free Tier' : 'De pago';
}

abstract final class GeminiModelCatalog {
  static const options = <GeminiModelOption>[
    GeminiModelOption(
      id: 'gemini-3.5-transcribe',
      name: 'Gemini 3.5 Transcribe · voz',
      specialized: true,
      freeTier: true,
    ),
    GeminiModelOption(
      id: 'gemini-3.5-flash-lite',
      name: 'Gemini 3.5 Flash-Lite',
      specialized: false,
      freeTier: true,
    ),
    GeminiModelOption(
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash',
      specialized: false,
      freeTier: true,
    ),
    GeminiModelOption(
      id: 'gemini-3.8-flash',
      name: 'Gemini 3.8 Flash',
      specialized: false,
      freeTier: true,
    ),
    GeminiModelOption(
      id: 'gemini-4-argon',
      name: 'Gemini 4 Argon',
      specialized: false,
      freeTier: false,
    ),
  ];

  static GeminiModelOption byId(String id) =>
      options.firstWhere((option) => option.id == id, orElse: () => options[2]);
}
