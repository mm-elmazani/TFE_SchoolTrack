/// Tests unitaires pour AuthProvider.
///
/// Verifie l'authentification, le stockage des tokens, le refresh,
/// le logout, et les helpers de role.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_teacher_app/core/api/api_client.dart';
import 'package:flutter_teacher_app/features/auth/providers/auth_provider.dart';

// ----------------------------------------------------------------
// Mocks
// ----------------------------------------------------------------

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

class MockApiClient extends Mock implements ApiClient {}

// ----------------------------------------------------------------
// Tests
// ----------------------------------------------------------------

void main() {
  late MockSecureStorage mockStorage;
  late MockApiClient mockApi;
  late AuthProvider provider;

  setUp(() {
    mockStorage = MockSecureStorage();
    mockApi = MockApiClient();
    provider = AuthProvider(storage: mockStorage, api: mockApi);

    // Stubs par defaut pour FlutterSecureStorage
    when(() => mockStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
    when(() => mockStorage.deleteAll()).thenAnswer((_) async {});
  });

  // ================================================================
  // Etat initial
  // ================================================================

  test('etat initial : pas authentifie, pas initialise', () {
    expect(provider.isAuthenticated, isFalse);
    expect(provider.isInitialized, isFalse);
    expect(provider.error, isNull);
    expect(provider.accessToken, isNull);
    expect(provider.userEmail, isNull);
  });

  // ================================================================
  // init
  // ================================================================

  group('AuthProvider.init', () {
    test('charge les tokens depuis le storage → authentifie', () async {
      when(() => mockStorage.read(key: 'access_token'))
          .thenAnswer((_) async => 'jwt-access');
      when(() => mockStorage.read(key: 'refresh_token'))
          .thenAnswer((_) async => 'jwt-refresh');
      when(() => mockStorage.read(key: 'user_email'))
          .thenAnswer((_) async => 'admin@test.be');
      when(() => mockStorage.read(key: 'user_role'))
          .thenAnswer((_) async => 'DIRECTION');
      when(() => mockStorage.read(key: 'user_first_name'))
          .thenAnswer((_) async => 'Jean');
      when(() => mockStorage.read(key: 'user_last_name'))
          .thenAnswer((_) async => 'Dupont');

      await provider.init();

      expect(provider.isInitialized, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.userEmail, 'admin@test.be');
      expect(provider.userRole, 'DIRECTION');
    });

    test('pas de tokens stockes → reste non authentifie', () async {
      await provider.init();

      expect(provider.isInitialized, isTrue);
      expect(provider.isAuthenticated, isFalse);
    });
  });

  // ================================================================
  // login
  // ================================================================

  group('AuthProvider.login', () {
    test('succes → stocke tokens et set authenticated', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'user': {
              'email': 'admin@test.be',
              'role': 'DIRECTION',
              'first_name': 'Jean',
              'last_name': 'Dupont',
            },
          });

      final result = await provider.login('admin@test.be', 'Admin123!');

      expect(result, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.accessToken, 'new-access');
      expect(provider.userEmail, 'admin@test.be');
      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('ApiException 2FA → error = 2FA_REQUIRED', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenThrow(const ApiException('2FA required', statusCode: 400));

      final result = await provider.login('admin@test.be', 'Admin123!');

      expect(result, isFalse);
      expect(provider.error, '2FA_REQUIRED');
    });

    test('ApiException autre → error = message', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenThrow(const ApiException('Mot de passe incorrect', statusCode: 401));

      final result = await provider.login('admin@test.be', 'wrong');

      expect(result, isFalse);
      expect(provider.error, 'Mot de passe incorrect');
    });

    test('erreur reseau → message generique', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenThrow(Exception('Network unreachable'));

      final result = await provider.login('admin@test.be', 'Admin123!');

      expect(result, isFalse);
      expect(provider.error, 'Impossible de contacter le serveur');
    });
  });

  // ================================================================
  // logout
  // ================================================================

  group('AuthProvider.logout', () {
    test('supprime tous les tokens et le storage', () async {
      // D'abord login
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok',
            'refresh_token': 'ref',
            'user': {'email': 'a@b.be', 'role': 'TEACHER', 'first_name': 'A', 'last_name': 'B'},
          });
      await provider.login('a@b.be', 'pass');
      expect(provider.isAuthenticated, isTrue);

      await provider.logout();

      expect(provider.isAuthenticated, isFalse);
      expect(provider.accessToken, isNull);
      expect(provider.userEmail, isNull);
      expect(provider.userRole, isNull);
      verify(() => mockStorage.deleteAll()).called(1);
    });
  });

  // ================================================================
  // refreshTokens
  // ================================================================

  group('AuthProvider.refreshTokens', () {
    test('succes → met a jour les tokens', () async {
      // Setup : simuler un login d'abord
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'old-access',
            'refresh_token': 'old-refresh',
            'user': {'email': 'a@b.be', 'role': 'DIRECTION', 'first_name': 'A', 'last_name': 'B'},
          });
      await provider.login('a@b.be', 'pass');

      when(() => mockApi.refreshToken(refreshToken: any(named: 'refreshToken')))
          .thenAnswer((_) async => {
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          });

      final result = await provider.refreshTokens();

      expect(result, isTrue);
      expect(provider.accessToken, 'new-access');
    });

    test('echec → declenche logout', () async {
      // Setup : simuler un login d'abord
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok',
            'refresh_token': 'ref',
            'user': {'email': 'a@b.be', 'role': 'DIRECTION', 'first_name': 'A', 'last_name': 'B'},
          });
      await provider.login('a@b.be', 'pass');

      when(() => mockApi.refreshToken(refreshToken: any(named: 'refreshToken')))
          .thenThrow(const ApiException('Invalid refresh token', statusCode: 401));

      final result = await provider.refreshTokens();

      expect(result, isFalse);
      expect(provider.isAuthenticated, isFalse);
    });

    test('pas de refresh token → retourne false', () async {
      // Pas de login → pas de refresh token
      final result = await provider.refreshTokens();

      expect(result, isFalse);
    });
  });

  // ================================================================
  // Helpers de role
  // ================================================================

  group('Helpers de role', () {
    test('isAdmin — DIRECTION est admin', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok', 'refresh_token': 'ref',
            'user': {'email': 'a@b.be', 'role': 'DIRECTION', 'first_name': 'A', 'last_name': 'B'},
          });
      await provider.login('a@b.be', 'pass');

      expect(provider.isAdmin, isTrue);
      expect(provider.isFieldUser, isTrue);
    });

    test('isAdmin — TEACHER n\'est pas admin', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok', 'refresh_token': 'ref',
            'user': {'email': 'a@b.be', 'role': 'TEACHER', 'first_name': 'A', 'last_name': 'B'},
          });
      await provider.login('a@b.be', 'pass');

      expect(provider.isAdmin, isFalse);
      expect(provider.isFieldUser, isTrue);
    });
  });

  // ================================================================
  // userDisplayName
  // ================================================================

  group('AuthProvider.userDisplayName', () {
    test('firstName + lastName → nom complet', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok', 'refresh_token': 'ref',
            'user': {'email': 'jean@test.be', 'role': 'DIRECTION', 'first_name': 'Jean', 'last_name': 'Dupont'},
          });
      await provider.login('jean@test.be', 'pass');

      expect(provider.userDisplayName, 'Jean Dupont');
    });

    test('pas de nom → fallback email', () async {
      when(() => mockApi.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
            totpCode: any(named: 'totpCode'),
            schoolSlug: any(named: 'schoolSlug'),
          )).thenAnswer((_) async => {
            'access_token': 'tok', 'refresh_token': 'ref',
            'user': {'email': 'noname@test.be', 'role': 'TEACHER', 'first_name': null, 'last_name': null},
          });
      await provider.login('noname@test.be', 'pass');

      expect(provider.userDisplayName, 'noname@test.be');
    });

    test('pas connecte → null', () {
      expect(provider.userDisplayName, isNull);
    });
  });

  // ================================================================
  // clearError
  // ================================================================

  test('clearError remet error a null', () async {
    when(() => mockApi.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
          totpCode: any(named: 'totpCode'),
          schoolSlug: any(named: 'schoolSlug'),
        )).thenThrow(const ApiException('Erreur', statusCode: 500));
    await provider.login('a@b.be', 'pass');
    expect(provider.error, isNotNull);

    provider.clearError();

    expect(provider.error, isNull);
  });
}
