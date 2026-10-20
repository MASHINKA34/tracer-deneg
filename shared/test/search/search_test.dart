import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('текст', () {
    test('нормализация: нижний регистр, ё → е, пробелы по краям', () {
      expect(normalizeSearchText('  Ёлка '), 'елка');
      expect(normalizeSearchText('ЁЖИК'), 'ежик');
      expect(normalizeSearchText('Кофе С Собой'), 'кофе с собой');
    });

    test('«ёлка» = «елка»', () {
      expect(textMatches('ёлка', 'Елка в офис'), isTrue);
      expect(textMatches('елка', 'ЁЛКА'), isTrue);
      expect(textMatches('Ёлка', 'новогодняя ёлка'), isTrue);
    });

    test('подстрока без учёта регистра; пустой запрос — всё', () {
      expect(textMatches('кофе', 'Кофе с собой'), isTrue);
      expect(textMatches('чай', 'Кофе'), isFalse);
      expect(textMatches('', 'что угодно'), isTrue);
      expect(textMatches('   ', 'что угодно'), isTrue);
    });
  });

  group('сумма', () {
    test('«640» находит 640 ₽, 640,50 ₽ и 6 400 ₽', () {
      expect(amountMatches('640', const Money.rubles(640)), isTrue);
      expect(amountMatches('640', const Money.rubles(640, 50)), isTrue);
      expect(amountMatches('640', const Money.rubles(6400)), isTrue);
      expect(amountMatches('640', const Money.rubles(64)), isFalse);
      expect(amountMatches('640', const Money.rubles(1640)), isFalse);
    });

    test('пробелы в запросе и ведущие нули не важны', () {
      expect(amountMatches('6 400', const Money.rubles(6400)), isTrue);
      expect(amountMatches('6 400', const Money.rubles(64000)), isTrue);
      expect(amountMatches('0640', const Money.rubles(640)), isTrue);
    });

    test('с запятой: рубли точно, копейки по началу', () {
      expect(amountMatches('149,9', const Money(14990)), isTrue);
      expect(amountMatches('149,9', const Money(14995)), isTrue);
      expect(amountMatches('149,9', const Money(14980)), isFalse);
      expect(amountMatches('149,9', const Money(149090)), isFalse);
      expect(amountMatches('149,', const Money(14900)), isTrue);
      expect(amountMatches('149,90', const Money(14990)), isTrue);
      expect(amountMatches('149,90', const Money(14991)), isFalse);
      expect(amountMatches('149.9', const Money(14990)), isTrue);
      expect(amountMatches('0,5', const Money(50)), isTrue);
    });

    test('не сумма — не совпадает', () {
      expect(amountMatches('кофе', const Money(100)), isFalse);
      expect(amountMatches('', const Money(100)), isFalse);
      expect(amountMatches('1,234', const Money(123400)), isFalse);
      expect(amountMatches('9' * 40, const Money(100)), isFalse);
      expect(amountMatches('${'9' * 40},5', const Money(100)), isFalse);
    });

    test('разбор запроса', () {
      expect(parseAmountQuery(' 6 400 '), const AmountQuery(rubles: '6400'));
      expect(
        parseAmountQuery('149,9'),
        const AmountQuery(rubles: '149', kopecks: '9'),
      );
      expect(
        parseAmountQuery('149,'),
        const AmountQuery(rubles: '149', kopecks: ''),
      );
      expect(parseAmountQuery('000'), const AmountQuery(rubles: '0'));
      expect(parseAmountQuery('abc'), isNull);
      expect(parseAmountQuery('149,9').hashCode, isA<int>());
      expect(parseAmountQuery('149,9').toString(), 'AmountQuery(149,9)');
    });
  });

  group('expenseMatches', () {
    bool match(String query) => expenseMatches(
      query: query,
      comment: 'Ёлка на дачу',
      categoryName: 'Подарки',
      amount: const Money.rubles(2340),
    );

    test('по комментарию, категории или сумме', () {
      expect(match('елка'), isTrue);
      expect(match('подар'), isTrue);
      expect(match('234'), isTrue);
      expect(match('кофе'), isFalse);
      expect(match('999'), isFalse);
    });
  });
}
