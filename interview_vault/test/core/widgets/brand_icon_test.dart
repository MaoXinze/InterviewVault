import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/widgets/brand_icon.dart';

/// 品牌线稿图标回归：底栏 4 Tab + 首页 3 快捷入口资产齐备、可着色渲染。
void main() {
  const names = [
    'nav_home',
    'nav_interviews',
    'nav_review',
    'nav_me',
    'qa_mic',
    'qa_import',
    'qa_mock',
  ];

  test('品牌图标资产齐备且为合法 SVG 文档', () async {
    for (final name in names) {
      final source =
          await rootBundle.loadString('assets/icons/$name.svg', cache: false);
      expect(source.startsWith('<svg'), isTrue, reason: '$name 不是 SVG 文档');
    }
  });

  testWidgets('BrandIcon 渲染且随传入色着色', (tester) async {
    for (final name in names) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: BrandIcon(name, color: Colors.amber)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SvgPicture), findsOneWidget, reason: name);
    }
  });
}
