int parseOpenApiInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

int? parseOpenApiNullableInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}

String parseOpenApiString(Object? value) {
  if (value is String) {
    return value;
  }
  return '';
}
