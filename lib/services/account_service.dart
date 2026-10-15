import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/config.dart';

/// Compte connecté (IMP-03).
class Account {
  final String id;
  final String email;
  final String name;

  const Account({required this.id, required this.email, required this.name});

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: (j['id'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}

/// Erreur lisible renvoyée à l'écran de compte.
class AccountException implements Exception {
  final String message;
  const AccountException(this.message);
  @override
  String toString() => message;
}

/// Comptes utilisateurs (IMP-03) : création, connexion, déconnexion, profil.
///
/// Le jeton de session et le compte sont conservés dans la boîte Hive
/// `settings` (stockage privé de l'application). Chaque mesure faite en
/// étant connecté porte l'identifiant du compte, localement et sur le
/// serveur : chaque compte retrouve ses mesures, et seulement les siennes.
class AccountService {
  static final ValueNotifier<Account?> current = ValueNotifier(_load());

  static Box? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static Account? _load() {
    try {
      final j = _box?.get('account');
      if (j is Map && _box?.get('accountToken') != null) {
        return Account.fromJson(Map<String, dynamic>.from(j));
      }
    } catch (_) {}
    return null;
  }

  /// À appeler une fois la boîte `settings` ouverte (main).
  static void reload() => current.value = _load();

  static String? get token => _box?.get('accountToken') as String?;
  static String? get currentId => current.value?.id;

  /// En-tête d'authentification à joindre aux requêtes, ou vide.
  static Map<String, String> get authHeaders =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  final Dio _dio = Dio(BaseOptions(
    baseUrl: API_BASE_URL,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 90),
  ));

  Future<Account> register(String email, String password, String name) =>
      _auth('/api/auth/register', {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
      });

  Future<Account> login(String email, String password) =>
      _auth('/api/auth/login', {'email': email.trim(), 'password': password});

  Future<Account> _auth(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      final data = Map<String, dynamic>.from(res.data as Map);
      final account =
          Account.fromJson(Map<String, dynamic>.from(data['user'] as Map));
      await _box?.put('accountToken', data['token']);
      await _box?.put('account', account.toJson());
      current.value = account;
      return account;
    } on DioException catch (e) {
      throw AccountException(_message(e));
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout',
          options: Options(headers: authHeaders));
    } catch (_) {
      // Hors ligne : la session expirera seule côté serveur.
    }
    await _clear();
  }

  Future<void> updateName(String name) async {
    try {
      final res = await _dio.put('/api/me',
          data: {'name': name.trim()}, options: Options(headers: authHeaders));
      final account = Account.fromJson(Map<String, dynamic>.from(res.data as Map));
      await _box?.put('account', account.toJson());
      current.value = account;
    } on DioException catch (e) {
      throw AccountException(_message(e));
    }
  }

  /// Supprime le compte. Ses mesures restent, rendues anonymes.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete('/api/me', options: Options(headers: authHeaders));
    } on DioException catch (e) {
      throw AccountException(_message(e));
    }
    await _clear();
  }

  /// Nombre de mesures rattachées au compte sur le serveur.
  Future<int?> serverResultCount() async {
    try {
      final res = await _dio.get('/api/me/results',
          queryParameters: {'limit': 1},
          options: Options(headers: authHeaders));
      return ((res.data as Map)['total'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  Future<void> _clear() async {
    await _box?.delete('accountToken');
    await _box?.delete('account');
    current.value = null;
  }

  String _message(DioException e) {
    switch (e.response?.statusCode) {
      case 400:
        return 'Vérifiez l\'adresse e-mail et le mot de passe (8 caractères '
            'au moins).';
      case 401:
        return 'E-mail ou mot de passe incorrect.';
      case 409:
        return 'Un compte existe déjà avec cette adresse e-mail.';
      case 429:
        return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }
    return 'Serveur injoignable. Vérifiez la connexion et réessayez.';
  }
}
