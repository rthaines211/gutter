import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/scan_status.dart';

void main() {
  test('scan status treats pipeline_running as busy', () {
    final s = ScanStatus.fromJson({'is_scanning': false, 'pipeline_running': true});
    expect(s.isScanning, false);
    expect(s.pipelineRunning, true);
    expect(s.isBusy, true);
    expect(ScanStatus.fromJson({}).isBusy, false);
  });
}
