import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final _rng = Random.secure();

class UserRecord {
  UserRecord({
    required this.email,
    required this.passwordSalt,
    required this.passwordHash,
    required this.createdAt,
    this.rewardBalance = 0,
  });

  final String email;
  final String passwordSalt;
  final String passwordHash;
  final String createdAt;
  int rewardBalance;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'email': email,
        'passwordSalt': passwordSalt,
        'passwordHash': passwordHash,
        'createdAt': createdAt,
        'rewardBalance': rewardBalance,
      };

  static UserRecord fromJson(Map<String, dynamic> json) {
    return UserRecord(
      email: json['email'] as String,
      passwordSalt: json['passwordSalt'] as String,
      passwordHash: json['passwordHash'] as String,
      createdAt: json['createdAt'] as String,
      rewardBalance: (json['rewardBalance'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserStore {
  UserStore(this._file);

  final File _file;
  final Map<String, UserRecord> _usersByEmail = <String, UserRecord>{};

  Future<void> load() async {
    if (!await _file.exists()) {
      await _file.parent.create(recursive: true);
      await _file.writeAsString('[]');
      return;
    }

    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    for (final entry in decoded) {
      final user = UserRecord.fromJson(entry as Map<String, dynamic>);
      _usersByEmail[user.email.toLowerCase()] = user;
    }
  }

  Future<void> save() async {
    final users = _usersByEmail.values
        .map((u) => u.toJson())
        .toList(growable: false)
      ..sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(users));
  }

  UserRecord? getByEmail(String email) {
    return _usersByEmail[email.toLowerCase()];
  }

  Future<void> add(UserRecord user) async {
    _usersByEmail[user.email.toLowerCase()] = user;
    await save();
  }

  Future<void> addReward(String email, int amount) async {
    final user = getByEmail(email);
    if (user == null) return;
    user.rewardBalance += amount;
    await save();
  }
}

String _generateSalt() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  return base64UrlEncode(bytes);
}

String _hashPassword(String password, String salt) {
  return sha256.convert(utf8.encode('$salt:$password')).toString();
}

String _b64NoPad(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _issueToken({required String email, required String secret}) {
  final payload = jsonEncode(<String, dynamic>{
    'sub': email,
    'exp': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
  });
  final payloadB64 = _b64NoPad(utf8.encode(payload));
  final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payloadB64));
  return '$payloadB64.${_b64NoPad(sig.bytes)}';
}

String? _validateToken(String token, String secret) {
  final parts = token.split('.');
  if (parts.length != 2) return null;

  final payloadB64 = parts[0];
  final providedSig = parts[1];

  final expectedSig = _b64NoPad(
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payloadB64)).bytes,
  );
  if (expectedSig != providedSig) return null;

  try {
    final normalized = payloadB64.padRight((payloadB64.length + 3) ~/ 4 * 4, '=');
    final payloadRaw = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
    final exp = (payload['exp'] as num).toInt();
    if (DateTime.now().millisecondsSinceEpoch > exp) return null;
    return payload['sub'] as String?;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _parseJsonBody(String body) {
  if (body.trim().isEmpty) return null;
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  return decoded;
}

Response _json(int status, Map<String, dynamic> body) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: const {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'content-type,authorization',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
    },
  );
}

Middleware _cors() {
  return (inner) {
    return (request) async {
      if (request.method == 'OPTIONS') {
        return _json(200, <String, dynamic>{'ok': true});
      }
      return inner(request);
    };
  };
}

Future<void> main() async {
  final host = Platform.environment['ZENITH_HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['ZENITH_PORT'] ?? '3000') ?? 3000;
  final secret = Platform.environment['ZENITH_JWT_SECRET'] ?? 'dev-secret-change-me';
  final dataPath = Platform.environment['ZENITH_DB_PATH'] ?? 'data/accounts.json';

  final store = UserStore(File(dataPath));
  await store.load();

  final router = Router();

  router.get('/health', (Request request) {
    return _json(200, <String, dynamic>{'status': 'ok', 'service': 'zenith-account-server'});
  });

  router.post('/api/register', (Request request) async {
    final data = _parseJsonBody(await request.readAsString());
    if (data == null) {
      return _json(400, <String, dynamic>{'error': 'Invalid JSON body'});
    }

    final email = (data['email'] as String? ?? '').trim().toLowerCase();
    final password = (data['password'] as String? ?? '').trim();
    if (email.isEmpty || password.length < 6 || !email.contains('@')) {
      return _json(400, <String, dynamic>{
        'error': 'Provide a valid email and a password with at least 6 characters',
      });
    }

    if (store.getByEmail(email) != null) {
      return _json(409, <String, dynamic>{'error': 'Account already exists'});
    }

    final salt = _generateSalt();
    final user = UserRecord(
      email: email,
      passwordSalt: salt,
      passwordHash: _hashPassword(password, salt),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await store.add(user);

    final token = _issueToken(email: email, secret: secret);
    return _json(201, <String, dynamic>{
      'token': token,
      'email': email,
      'rewardBalance': 0,
    });
  });

  router.post('/api/login', (Request request) async {
    final data = _parseJsonBody(await request.readAsString());
    if (data == null) {
      return _json(400, <String, dynamic>{'error': 'Invalid JSON body'});
    }

    final email = (data['email'] as String? ?? '').trim().toLowerCase();
    final password = (data['password'] as String? ?? '').trim();
    final user = store.getByEmail(email);
    if (user == null) {
      return _json(401, <String, dynamic>{'error': 'Invalid credentials'});
    }

    final hash = _hashPassword(password, user.passwordSalt);
    if (hash != user.passwordHash) {
      return _json(401, <String, dynamic>{'error': 'Invalid credentials'});
    }

    final token = _issueToken(email: email, secret: secret);
    return _json(200, <String, dynamic>{
      'token': token,
      'email': email,
      'rewardBalance': user.rewardBalance,
    });
  });

  router.post('/api/forgot-password', (Request request) async {
    final data = _parseJsonBody(await request.readAsString());
    final email = (data?['email'] as String? ?? '').trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      return _json(400, <String, dynamic>{'error': 'Provide a valid email'});
    }

    // Prototype flow: acknowledge request without leaking account existence.
    return _json(200, <String, dynamic>{
      'message':
          'Reset requested. For now, contact support@zenith-app.net from your account email.',
    });
  });

  router.get('/api/me', (Request request) {
    final authHeader = request.headers['authorization'] ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return _json(401, <String, dynamic>{'error': 'Missing bearer token'});
    }

    final token = authHeader.substring('Bearer '.length).trim();
    final email = _validateToken(token, secret);
    if (email == null) {
      return _json(401, <String, dynamic>{'error': 'Invalid or expired token'});
    }

    final user = store.getByEmail(email);
    if (user == null) {
      return _json(404, <String, dynamic>{'error': 'User not found'});
    }

    return _json(200, <String, dynamic>{
      'email': user.email,
      'rewardBalance': user.rewardBalance,
      'createdAt': user.createdAt,
    });
  });

  router.post('/api/reward', (Request request) async {
    final authHeader = request.headers['authorization'] ?? '';
    if (!authHeader.startsWith('Bearer ')) {
      return _json(401, <String, dynamic>{'error': 'Missing bearer token'});
    }

    final token = authHeader.substring('Bearer '.length).trim();
    final email = _validateToken(token, secret);
    if (email == null) {
      return _json(401, <String, dynamic>{'error': 'Invalid or expired token'});
    }

    final data = _parseJsonBody(await request.readAsString());
    final amount = (data?['amount'] as num?)?.toInt() ?? 0;
    if (amount <= 0) {
      return _json(400, <String, dynamic>{'error': 'amount must be > 0'});
    }

    await store.addReward(email, amount);
    final user = store.getByEmail(email)!;
    return _json(200, <String, dynamic>{
      'email': email,
      'rewardBalance': user.rewardBalance,
    });
  });

  router.get('/', (Request request) async {
    final file = File('web/index.html');
    if (!await file.exists()) {
      return Response.notFound('Missing web/index.html');
    }
    return Response.ok(
      await file.readAsString(),
      headers: const {'content-type': 'text/html; charset=utf-8'},
    );
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(router.call);

  final server = await io.serve(handler, host, port);
  stdout.writeln('Zenith account server running on http://${server.address.host}:${server.port}');
}
