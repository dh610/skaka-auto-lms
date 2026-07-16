enum CampusRegion {
  pangyo4f(id: 'P1', label: '판교캠퍼스 4F', classNumbers: [1, 2, 3, 4, 5]),
  pangyo5f(id: 'P2', label: '판교캠퍼스 5F', classNumbers: [6, 7, 8, 9, 10]);

  const CampusRegion({
    required this.id,
    required this.label,
    required this.classNumbers,
  });

  factory CampusRegion.fromId(String id) {
    return CampusRegion.values.firstWhere((region) => region.id == id);
  }

  final String id;
  final String label;
  final List<int> classNumbers;
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.region,
    required this.classNumber,
  });

  final String name;
  final CampusRegion region;
  final int classNumber;

  String get classLabel => '$classNumber반';
  String get subGroupId => '$classNumber';
}
