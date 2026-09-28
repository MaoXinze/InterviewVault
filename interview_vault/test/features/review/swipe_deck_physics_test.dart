import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/features/review/presentation/swipe_deck.dart';

void main() {
  group('commitSwipe 阈值判定', () {
    test('拖动超过宽度 45% 提交', () {
      expect(commitSwipe(dx: 0.46 * 800, width: 800, vx: 0), isTrue);
      expect(commitSwipe(dx: 0.44 * 800, width: 800, vx: 0), isFalse);
    });

    test('快速轻扫（flick）超过 15% 即提交', () {
      expect(commitSwipe(dx: 0.2 * 800, width: 800, vx: 1200), isTrue);
      // 慢速同样的位移不提交
      expect(commitSwipe(dx: 0.2 * 800, width: 800, vx: 300), isFalse);
      // 快速但位移不足不提交
      expect(commitSwipe(dx: 0.1 * 800, width: 800, vx: 1200), isFalse);
    });

    test('方向无关：左滑同样按绝对值判定', () {
      expect(commitSwipe(dx: -0.46 * 800, width: 800, vx: 0), isTrue);
      expect(commitSwipe(dx: -0.2 * 800, width: 800, vx: -1200), isTrue);
    });
  });

  group('swipeCardTransform 拖动形变', () {
    test('静止时恒等矩阵（不影响既有翻面合成）', () {
      final m = swipeCardTransform(dx: 0, width: 800, squish: 0);
      expect(m.entry(0, 0), moreOrLessEquals(1.0));
      expect(m.entry(1, 1), moreOrLessEquals(1.0));
      expect(m.entry(0, 1), moreOrLessEquals(0.0));
    });

    test('拖动中产生 rotateZ 倾斜（非对角项非零）', () {
      final m = swipeCardTransform(dx: 200, width: 800, squish: 0);
      expect(m.entry(0, 1).abs(), greaterThan(0.01),
          reason: 'rotateZ 倾斜应产生非对角分量');
    });

    test('速度形变：沿拖动轴拉伸、垂直轴压缩（非等比缩放）', () {
      final m = swipeCardTransform(dx: 0, width: 800, squish: 30);
      // sx = 1 + 30*0.0011 ≈ 1.033；sy = 1 - (sx-1)*0.75 ≈ 0.975
      expect(m.entry(0, 0), greaterThan(1.01), reason: '拖动轴应拉伸');
      expect(m.entry(1, 1), lessThan(0.99), reason: '垂直轴应压缩');
      // 等比保护：压缩幅度小于拉伸幅度（保持体积感不塌陷）
      final stretch = m.entry(0, 0) - 1;
      final squash = 1 - m.entry(1, 1);
      expect(squash, lessThan(stretch));
    });

    test('形变封顶：极快拖动不超过 5% 拉伸（文字不失真）', () {
      final m = swipeCardTransform(dx: 0, width: 800, squish: 999);
      expect(m.entry(0, 0), lessThanOrEqualTo(1.05));
    });

    test('倾斜封顶：整宽拖动约 7°（0.12rad），两方向对称', () {
      final right = swipeCardTransform(dx: 800, width: 800, squish: 0);
      final left = swipeCardTransform(dx: -800, width: 800, squish: 0);
      // M01 = sx · (−sin θ)，θ = 0.12rad → |M01| ≈ 0.1197；右滑与左滑镜像
      expect(right.entry(0, 1).abs(), moreOrLessEquals(0.1197, epsilon: 0.01));
      expect(right.entry(0, 1), -left.entry(0, 1));
    });
  });

  group('deckBehindTransform 背后卡片视差', () {
    test('静止：下沉 6px 露出底边（卡片堆隐喻），不缩放', () {
      final m = deckBehindTransform(0);
      expect(m.entry(0, 0), moreOrLessEquals(1.0));
      expect(m.entry(1, 1), moreOrLessEquals(1.0));
      expect(m.entry(1, 3), moreOrLessEquals(6.0));
    });

    test('拖动到底：收拢回正，飞出后新卡可从 0.96 无缝落位', () {
      final m = deckBehindTransform(1);
      expect(m.entry(1, 3), moreOrLessEquals(0.0));
      expect(m.entry(0, 0), moreOrLessEquals(0.96));
    });

    test('进度钳制：超界拖动不越界收拢', () {
      final over = deckBehindTransform(5).entry(0, 0);
      expect(over, moreOrLessEquals(deckBehindTransform(1).entry(0, 0)));
    });
  });
}
