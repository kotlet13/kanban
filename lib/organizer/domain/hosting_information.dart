/// Public hosting disclosure. These claims come from the selected server;
/// they never establish an independently verified operator identity.
class HostingInformation {
  const HostingInformation({this.operatorName, this.operatorContact});

  factory HostingInformation.fromCapabilities(Map<String, dynamic> caps) {
    final value = caps['hostingInformation'];
    if (value is! Map) return const HostingInformation();
    return HostingInformation(
      operatorName: _text(value['operatorName']),
      operatorContact: _text(value['operatorContact']),
    );
  }

  final String? operatorName, operatorContact;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    // Metadata is plain, bounded, single-line text, including for old or
    // independently hosted servers. Reject bidi/control spoofing characters.
    if (text.isEmpty ||
        text.length > 300 ||
        RegExp(
          r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]',
        ).hasMatch(text)) {
      return null;
    }
    return text;
  }
}
