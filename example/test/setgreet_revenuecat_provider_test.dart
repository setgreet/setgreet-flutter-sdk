import 'package:example/setgreet_revenuecat_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('playProductName drops the app name Google Play appends', () {
    String name(String title) =>
        SetgreetRevenueCatProvider.playProductName(title);

    test('the trailing group goes', () {
      expect(name('Premium Annual (Your App)'), 'Premium Annual');
      expect(name('Premium Annual (Your App)  '), 'Premium Annual');
    });

    test("the product's own parentheses survive", () {
      expect(name('Pro (Annual) (Your App)'), 'Pro (Annual)');
      expect(
          name('Pro (2 devices) Annual (Your App)'), 'Pro (2 devices) Annual');
    });

    test('a nested app name goes as a whole', () {
      expect(name('Pro (Your App (Beta))'), 'Pro');
      expect(name('Pro (Annual) (Your (Best) App)'), 'Pro (Annual)');
    });

    test('a title without a trailing group is unchanged', () {
      expect(name('Premium Annual'), 'Premium Annual');
      expect(name('Premium (Annual) plan'), 'Premium (Annual) plan');
      expect(name(''), '');
    });

    test('an unbalanced or bare group is unchanged', () {
      expect(name('Premium Annual Your App)'), 'Premium Annual Your App)');
      expect(name('Premium (Your App))'), 'Premium (Your App))');
      expect(name('(Your App)'), '(Your App)');
    });
  });
}
