// To parse this JSON data, do
//
//     final lastTransaction = lastTransactionFromJson(jsonString);

import 'dart:convert';

LastTransaction lastTransactionFromJson(String str) =>
    LastTransaction.fromJson(json.decode(str));

String lastTransactionToJson(LastTransaction data) =>
    json.encode(data.toJson());

class LastTransaction {
  bool ok;
  Data data;

  LastTransaction({required this.ok, required this.data});

  factory LastTransaction.fromJson(Map<String, dynamic> json) =>
      LastTransaction(ok: json["ok"], data: Data.fromJson(json["data"]));

  Map<String, dynamic> toJson() => {"ok": ok, "data": data.toJson()};
}

class Data {
  int id;
  String empCode;
  DateTime punchTime;

  Data({required this.id, required this.empCode, required this.punchTime});

  factory Data.fromJson(Map<String, dynamic> json) => Data(
    id: json["id"],
    empCode: json["emp_code"],
    punchTime: DateTime.parse(json['punch_time']).toLocal(),
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "emp_code": empCode,
    "punch_time": punchTime.toIso8601String(),
  };
}
