class Employee {
  final int? id;
  final String name;
  final String idNumber; // staff ID digits without "UUDS-" prefix; '' if none on file
  Employee({this.id, required this.name, this.idNumber = ''});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'idNumber': idNumber};
  factory Employee.fromMap(Map<String, dynamic> m) => Employee(
        id: m['id'] as int?,
        name: m['name'] as String,
        idNumber: (m['idNumber'] as String?) ?? '',
      );
}

class Aircraft {
  final int? id;
  final String regNo; // e.g. A6-ABC
  Aircraft({this.id, required this.regNo});

  Map<String, dynamic> toMap() => {'id': id, 'regNo': regNo};
  factory Aircraft.fromMap(Map<String, dynamic> m) =>
      Aircraft(id: m['id'] as int?, regNo: m['regNo'] as String);
}

class PartLocation {
  final int? id;
  final String name;
  PartLocation({this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};
  factory PartLocation.fromMap(Map<String, dynamic> m) =>
      PartLocation(id: m['id'] as int?, name: m['name'] as String);
}

enum InspectionType { receiving, dispatch }

extension InspectionTypeLabel on InspectionType {
  String get label =>
      this == InspectionType.receiving ? 'Receiving' : 'Dispatch';
}

class InspectionPhoto {
  final int? id;
  final String employeeName;
  final String aircraftReg;
  final String inspectionType; // 'Receiving' or 'Dispatch'
  final String partLocation;
  final String filePath;
  final String timestamp; // ISO8601
  final String remarks;
  final String tagPartNo;
  final String tagDescription;
  final String tagLocation;
  final String tagQty;

  InspectionPhoto({
    this.id,
    required this.employeeName,
    required this.aircraftReg,
    required this.inspectionType,
    required this.partLocation,
    required this.filePath,
    required this.timestamp,
    this.remarks = '',
    this.tagPartNo = '',
    this.tagDescription = '',
    this.tagLocation = '',
    this.tagQty = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'employeeName': employeeName,
        'aircraftReg': aircraftReg,
        'inspectionType': inspectionType,
        'partLocation': partLocation,
        'filePath': filePath,
        'timestamp': timestamp,
        'remarks': remarks,
        'tagPartNo': tagPartNo,
        'tagDescription': tagDescription,
        'tagLocation': tagLocation,
        'tagQty': tagQty,
      };

  factory InspectionPhoto.fromMap(Map<String, dynamic> m) => InspectionPhoto(
        id: m['id'] as int?,
        employeeName: m['employeeName'] as String,
        aircraftReg: m['aircraftReg'] as String,
        inspectionType: m['inspectionType'] as String,
        partLocation: m['partLocation'] as String,
        filePath: m['filePath'] as String,
        timestamp: m['timestamp'] as String,
        remarks: (m['remarks'] as String?) ?? '',
        tagPartNo: (m['tagPartNo'] as String?) ?? '',
        tagDescription: (m['tagDescription'] as String?) ?? '',
        tagLocation: (m['tagLocation'] as String?) ?? '',
        tagQty: (m['tagQty'] as String?) ?? '',
      );
}
