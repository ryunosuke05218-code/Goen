class AssistantRouteStep {
  AssistantRouteStep({required this.personId, required this.personName, this.relationTypeFromPrevious});

  final String personId;
  final String personName;
  final String? relationTypeFromPrevious;

  factory AssistantRouteStep.fromJson(Map<String, dynamic> json) => AssistantRouteStep(
        personId: json['personId'] as String,
        personName: json['personName'] as String,
        relationTypeFromPrevious: json['relationTypeFromPrevious'] as String?,
      );
}

class AssistantRoute {
  AssistantRoute({required this.steps});

  final List<AssistantRouteStep> steps;

  factory AssistantRoute.fromJson(Map<String, dynamic> json) => AssistantRoute(
        steps: (json['steps'] as List).map((e) => AssistantRouteStep.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class AssistantHint {
  AssistantHint({required this.personId, required this.personName, required this.reason, required this.excerpt});

  final String personId;
  final String personName;
  final String reason;
  final String excerpt;

  factory AssistantHint.fromJson(Map<String, dynamic> json) => AssistantHint(
        personId: json['personId'] as String,
        personName: json['personName'] as String,
        reason: json['reason'] as String,
        excerpt: json['excerpt'] as String,
      );
}

class AssistantResult {
  AssistantResult({required this.answer, required this.routes, required this.hints});

  final String answer;
  final List<AssistantRoute> routes;
  final List<AssistantHint> hints;

  factory AssistantResult.fromJson(Map<String, dynamic> json) => AssistantResult(
        answer: json['answer'] as String,
        routes: (json['routes'] as List).map((e) => AssistantRoute.fromJson(e as Map<String, dynamic>)).toList(),
        hints: (json['hints'] as List).map((e) => AssistantHint.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
