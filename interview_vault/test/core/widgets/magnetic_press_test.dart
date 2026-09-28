import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/widgets/motion.dart';

void main() {
  Future<void> pumpMagnetic(
    WidgetTester tester, {
    required VoidCallback onTap,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: MagneticPress(
                child: TextButton(
                  key: const Key('btn'),
                  onPressed: onTap,
                  child: const Text('action'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 文本相对 MagneticPress 的 x 平移：含按钮固有内边距偏移（恒量），
  /// 断言一律用相对手势前基线的增量（增量即磁吸位移）。
  double translationDx(WidgetTester tester) => tester
      .renderObject<RenderBox>(find.text('action'))
      .getTransformTo(tester.renderObject<RenderBox>(find.byType(MagneticPress)))
      .entry(0, 3);

  testWidgets('按住拖动：按钮向指尖微移，松手回弹且点击照常触发', (tester) async {
    var tapped = 0;
    await pumpMagnetic(tester, onTap: () => tapped++);

    final baseline = translationDx(tester);
    final center = tester.getCenter(find.byKey(const Key('btn')));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(6, 0));
    await tester.pump();

    // 磁吸：按钮被吸向指尖（向右位移 > 0）
    expect(translationDx(tester) - baseline, greaterThan(0),
        reason: '按住拖动时按钮应向指尖微移');

    await gesture.up();
    await tester.pumpAndSettle();

    // 磁吸跟手 → 松手仍在按钮上，点击不丢
    expect(tapped, 1);
    // 回弹出口：松手后位移归零
    expect(translationDx(tester) - baseline, moreOrLessEquals(0.0));
  });

  testWidgets('位移封顶：大距离拖动不超过 maxOffset（磁而不晃）', (tester) async {
    var tapped = 0;
    await pumpMagnetic(tester, onTap: () => tapped++);

    final baseline = translationDx(tester);
    final center = tester.getCenter(find.byKey(const Key('btn')));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    final shift = translationDx(tester) - baseline;
    expect(shift, greaterThan(0));
    expect(shift, lessThanOrEqualTo(6.0));
    // 超出拖动斜度（>18px）：按钮自行取消点击，松手不触发
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tapped, 0);
    expect(translationDx(tester) - baseline, moreOrLessEquals(0.0));
  });

  testWidgets('减弱动态效果：不吸附，点击不受影响', (tester) async {
    var tapped = 0;
    await pumpMagnetic(
      tester,
      onTap: () => tapped++,
      disableAnimations: true,
    );

    final baseline = translationDx(tester);
    final center = tester.getCenter(find.byKey(const Key('btn')));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(6, 0));
    await tester.pump();

    expect(translationDx(tester) - baseline, moreOrLessEquals(0.0),
        reason: '减弱动态效果下应为静态按钮');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
