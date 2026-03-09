import 'package:flutter/material.dart';

enum Gender { female, male }

extension GenderUi on Gender {
  String get label => switch (this) {
        Gender.female => 'Female',
        Gender.male => 'Male',
      };

  IconData get icon => switch (this) {
        Gender.female => Icons.female,
        Gender.male => Icons.male,
      };

  Color get tone => switch (this) {
        Gender.female => const Color(0xFFEAF3FF),
        Gender.male => const Color(0xFFEFF8F1),
      };

  Gender get opposite => switch (this) {
        Gender.female => Gender.male,
        Gender.male => Gender.female,
      };
}
