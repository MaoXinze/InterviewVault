import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/widgets/illustration.dart';

/// 鎏金线稿插画回归：7 种变体的资产可加载、可解析、可渲染。
void main() {
  // pubspec assets 目录下应存在的插画（新增插画后在此登记）
  const assets = [
    'assets/illustrations/flip_question.svg',
    'assets/illustrations/flip_answer.svg',
    'assets/illustrations/review_done.svg',
    'assets/illustrations/empty_interviews.svg',
    'assets/illustrations/mock_coach.svg',
    'assets/illustrations/mic_wave.svg',
    'assets/illustrations/idea_bulb.svg',
  ];

  test('插画资产齐备且为合法 SVG 文档', () async {
    for (final asset in assets) {
      final source = await rootBundle.loadString(asset, cache: false);
      expect(source.startsWith('<svg'), isTrue, reason: '$asset 不是 SVG 文档');
    }
  });

  testWidgets('CardIllustration 各变体渲染为 SvgPicture 且不抛异常', (tester) async {
    final variants = <Widget>[
      const CardIllustration.question(),
      const CardIllustration.answer(),
      const CardIllustration.done(),
      const CardIllustration.interviews(),
      const CardIllustration.coach(),
      const CardIllustration.mic(),
      const CardIllustration.bulb(),
    ];
    for (final variant in variants) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: variant))),
      );
      await tester.pump();
      expect(find.byType(SvgPicture), findsOneWidget);
    }
  });
}
