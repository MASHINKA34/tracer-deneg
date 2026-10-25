import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/deep_link.dart';
import 'package:milionchik/core/router.dart';

DeepLinkTarget? _target(String link) => DeepLink.of(Uri.parse(link))?.target;

void main() {
  test('milionchik://add и milionchik://month распознаются, query, '
      'фрагмент и косая черта в конце не мешают', () {
    for (final link in [
      'milionchik://add',
      'milionchik://add/',
      'milionchik://add?from=widget',
      'milionchik://add#top',
      'MILIONCHIK://ADD',
    ]) {
      expect(_target(link), DeepLinkTarget.add, reason: link);
    }
    for (final link in [
      'milionchik://month',
      'milionchik://month/',
      'milionchik://month?from=notification',
    ]) {
      expect(_target(link), DeepLinkTarget.month, reason: link);
    }
  });

  test('чужие хосты, пути и схемы — неизвестная ссылка', () {
    for (final link in [
      'milionchik://unknown',
      'milionchik://add/extra',
      'milionchik://month/2026-10',
      'milionchik://expense/new',
      'milionchik:///add',
      'milionchik:add',
      'milionchik://',
      'https://add',
      'https://milionchik.ru/month',
      'intent://add',
    ]) {
      final parsed = DeepLink.of(Uri.parse(link));
      expect(parsed, isNotNull, reason: link);
      expect(parsed!.target, isNull, reason: link);
    }
  });

  test('адреса внутри приложения — не ссылки', () {
    for (final location in [
      AppRoutes.month,
      AppRoutes.newExpense,
      '/add',
      '/month?date=2026-10-19',
      '/',
    ]) {
      expect(DeepLink.of(Uri.parse(location)), isNull, reason: location);
    }
  });

  test('для лога — только схема, хост и путь: без query, фрагмента, '
      'имени пользователя и порта', () {
    String place(String link) => DeepLink.of(Uri.parse(link))!.place;

    expect(place('milionchik://add'), 'milionchik://add');
    expect(place('milionchik://add/'), 'milionchik://add');
    expect(
      place('milionchik://add?comment=QUERY-VALUE-ZULU#FRAGMENT-ZULU'),
      'milionchik://add',
    );
    expect(
      place('milionchik://USERINFO-ZULU@month:8080'),
      'milionchik://month',
    );
    expect(place('milionchik://unknown/a/b'), 'milionchik://unknown/a/b');
    expect(place('milionchik:add'), 'milionchik:add');
    expect(place('https://example.org/x'), 'https://example.org/x');
  });

  test('длинный путь в логе обрезается с указанием полной длины', () {
    final link = 'milionchik://unknown/${'a' * 200}';
    final place = DeepLink.of(Uri.parse(link))!.place;

    expect(place, startsWith('milionchik://unknown/aaaa'));
    expect(place, endsWith('…(${link.length} chars)'));
    expect(place.length, lessThan(maxDeepLinkPlaceLength + 20));
  });

  test('isAddExpenseLink: путь после хоста add — уже не «Новая трата»', () {
    expect(isAddExpenseLink(Uri.parse('milionchik://add')), isTrue);
    expect(isAddExpenseLink(Uri.parse('milionchik://add/extra')), isFalse);
  });
}
