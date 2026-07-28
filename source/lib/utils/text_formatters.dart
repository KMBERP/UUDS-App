import 'package:flutter/services.dart';

/// Forces whatever is typed into a TextField to appear in capital letters,
/// live as you type - not just a keyboard hint (which only affects the
/// keyboard's shift state, not what actually gets typed if you override
/// it). Apply via `inputFormatters: [upperCaseInputFormatter]` on any
/// data-entry field that should always be capitals: aircraft registration,
/// inspector name, part location, tag part no/description, remarks, etc.
final upperCaseInputFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
);
