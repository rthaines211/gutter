import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/config/server_config.dart';

void main() {
  test('no stored url and no define -> empty default', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ServerConfig(await SharedPreferences.getInstance());
    expect(c.serverUrl, '');
  });

  test('stored url wins over the built-in default', () async {
    SharedPreferences.setMockInitialValues({'server_url': 'https://my.server'});
    final c = ServerConfig(await SharedPreferences.getInstance());
    expect(c.serverUrl, 'https://my.server');
  });
}
