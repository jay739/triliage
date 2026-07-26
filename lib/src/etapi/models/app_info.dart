/// Server identity returned by `GET /etapi/app-info`.
///
/// This is the cheapest authenticated call ETAPI offers, which makes it the
/// natural probe for "is this URL a Trilium server, and does this token work".
class AppInfo {
  const AppInfo({
    required this.appVersion,
    required this.dbVersion,
    this.syncVersion,
    this.buildDate,
    this.clipperProtocolVersion,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      appVersion: json['appVersion'] as String? ?? 'unknown',
      dbVersion: (json['dbVersion'] as num?)?.toInt() ?? 0,
      syncVersion: (json['syncVersion'] as num?)?.toInt(),
      buildDate: json['buildDate'] as String?,
      clipperProtocolVersion: json['clipperProtocolVersion'] as String?,
    );
  }

  final String appVersion;
  final int dbVersion;
  final int? syncVersion;
  final String? buildDate;
  final String? clipperProtocolVersion;
}
