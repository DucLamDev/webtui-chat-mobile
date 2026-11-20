import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_profile_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/markdown/ide_chart_view.dart';

void main() {
  test('tiền VND tiếng Việt: nghìn, triệu, tỷ', () {
    expect(ideFormatVnd(850000), '850.000 đ');
    expect(ideFormatVnd(0), '0 đ');
    expect(ideFormatVnd(999999), '999.999 đ');
    expect(ideFormatVnd(1100000), '1,1 triệu đ');
    expect(ideFormatVnd(2000000), '2 triệu đ');
    expect(ideFormatVnd(1200000000), '1,2 tỷ đ');
    expect(ideFormatVnd(null), '—');
    expect(ideFormatVnd(double.nan), '—');
  });

  test('tiền VND tiếng Anh: kiểu gọn', () {
    expect(ideFormatVnd(1100000, english: true), '1.1M VND');
    expect(ideFormatVnd(2500000000, english: true), '2.5B VND');
    expect(ideFormatVnd(850000, english: true), '850.000 VND');
  });

  test('biểu đồ: quá 60 điểm thì bỏ chấm tròn', () {
    expect(ideChartShowDots(60), isTrue);
    expect(ideChartShowDots(61), isFalse);
    expect(ideChartShowDots(5), isTrue);
  });
}
