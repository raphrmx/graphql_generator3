import 'package:graphql_generator3/src/string_case.dart';
import 'package:test/test.dart';

void main() {
  group('camelCase', () {
    test('lowers the first word of a PascalCase name', () {
      expect(camelCase('BmcBddEmployee'), 'bmcBddEmployee');
      expect(camelCase('Company'), 'company');
    });

    test('treats an all-caps input as a single word', () {
      expect(camelCase('SDL'), 'sdl');
      expect(camelCase('VAT_NO'), 'vatNo');
    });

    test('splits on separators and drops them', () {
      expect(camelCase('provider_account_model'), 'providerAccountModel');
      expect(camelCase('provider-account.model'), 'providerAccountModel');
      expect(camelCase('provider account'), 'providerAccount');
    });

    test('drops a leading underscore, as a private class name carries', () {
      expect(camelCase('_ProviderAccount'), 'providerAccount');
    });

    test('keeps only the first letter of a word upper-case', () {
      expect(camelCase('FDMData'), 'fDMData');
      expect(camelCase('HTTPServer'), 'hTTPServer');
    });

    test('keeps digits attached to the word they follow', () {
      expect(camelCase('Fdm09Report'), 'fdm09Report');
    });

    test('answers an empty string for an empty input', () {
      expect(camelCase(''), '');
    });
  });

  group('snakeCase', () {
    test('separates words with an underscore', () {
      expect(snakeCase('BmcDeviceData'), 'bmc_device_data');
      expect(snakeCase('bookingDateData'), 'booking_date_data');
    });

    test('treats an all-caps input as a single word', () {
      expect(snakeCase('SDL'), 'sdl');
    });

    test('normalises input that already carries separators', () {
      expect(snakeCase('provider-account'), 'provider_account');
      expect(snakeCase('_ProviderAccount'), 'provider_account');
    });

    test('answers an empty string for an empty input', () {
      expect(snakeCase(''), '');
    });
  });
}
