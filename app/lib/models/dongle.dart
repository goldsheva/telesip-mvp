class Dongle {
  final int id;
  final String title;

  const Dongle({required this.id, required this.title});

  factory Dongle.fromJson(Map<String, dynamic> json) {
    return Dongle(
      id: json['id'] as int,
      title: (json['title'] ?? json['name'] ?? '').toString(),
    );
  }
}
