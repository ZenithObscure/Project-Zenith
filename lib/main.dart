import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

const String kGitHubReleasesUrl =
    'https://github.com/ZenithObscure/Project-Zenith/releases/latest';
const String kGitHubApiReleasesUrl =
    'https://api.github.com/repos/ZenithObscure/Project-Zenith/releases/latest';
const String kCurrentVersion = '0.1.0';
const String kDefaultLocalLlmEndpoint = String.fromEnvironment(
  'ZENITH_LOCAL_LLM_ENDPOINT',
  defaultValue: 'http://127.0.0.1:11434',
);
const String kDefaultLocalLlmModel = String.fromEnvironment(
  'ZENITH_LOCAL_LLM_MODEL',
  defaultValue: 'qwen2.5-coder:7b',
);
const String kDefaultAccountServerUrl = String.fromEnvironment(
  'ZENITH_ACCOUNT_SERVER_URL',
  defaultValue: 'https://zenith-app.net',
);
const double kDefaultStorageReservedGb = 128;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<AppController> _controllerFuture;

  @override
  void initState() {
    super.initState();
    _controllerFuture = AppController.create();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        final controller = snapshot.data;
        if (controller == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Loading Project Zenith...'),
                  ],
                ),
              ),
            ),
          );
        }

        return ZenithScope(
          controller: controller,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return MaterialApp(
                title: 'Project Zenith',
                debugShowCheckedModeBanner: false,
                themeMode:
                    controller.darkMode ? ThemeMode.dark : ThemeMode.light,
                theme: ThemeData(
                  colorScheme:
                      ColorScheme.fromSeed(seedColor: controller.seedColor),
                  useMaterial3: true,
                ),
                darkTheme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: controller.seedColor,
                    brightness: Brightness.dark,
                  ),
                  useMaterial3: true,
                ),
                home: const AuthGate(),
              );
            },
          ),
        );
      },
    );
  }
}

class AppController extends ChangeNotifier {
  AppController._(this._prefs);

  final SharedPreferences _prefs;

  static const _kUserEmail = 'userEmail';
  static const _kAuthToken = 'authToken';
  static const _kAccountServerUrl = 'accountServerUrl';
  static const _kSavedFidusChats = 'savedFidusChats';
  static const _kStorageDedicatedGb = 'storageDedicatedGb';
  static const _kSeedColor = 'seedColor';
  static const _kDarkMode = 'darkMode';
  static const _kEngineNode = 'engineNode';
  static const _kEngineCpuCores = 'engineCpuCores';
  static const _kEngineRamGb = 'engineRamGb';
  static const _kEnginePreferRemote = 'enginePreferRemote';
  static const _kAlbumAutoBackup = 'albumAutoBackup';
  static const _kDriveSyncEnabled = 'driveSyncEnabled';
  static const _kModelId = 'modelId';
  static const _kModelLoaded = 'modelLoaded';
  static const _kNodeEndpoint = 'nodeEndpoint';
  static const _kNodePairingToken = 'nodePairingToken';
  static const _kNodeConnected = 'nodeConnected';
  static const _kUseRemoteNode = 'useRemoteNode';
  static const _kDeviceId = 'deviceId';
  static const _kLocalLlmEnabled = 'localLlmEnabled';
  static const _kLocalLlmEndpoint = 'localLlmEndpoint';
  static const _kLocalLlmModel = 'localLlmModel';

  String? userEmail;
  String? authToken;
  String accountServerUrl = kDefaultAccountServerUrl;
  List<FidusChatSession> savedFidusChats = [];

  double storageDedicatedGb = kDefaultStorageReservedGb;
  double storageAvailableGb = 0;
  double storageTotalGb = 0;
  bool storageStatsReady = false;
  Color seedColor = Colors.teal;
  bool darkMode = false;

  String engineNode = 'This device';
  double engineCpuCores = 2;
  double engineRamGb = 4;
  bool enginePreferRemote = true;

  String? modelId;
  bool modelLoaded = false;
  double modelDownloadProgress = 0.0;
  bool modelDownloading = false;

  String? nodeEndpoint;
  String? nodePairingToken;
  bool nodeConnected = false;
  bool useRemoteNode = false;
  String nodeStatus = 'Not configured';

  bool localLlmEnabled = true;
  String localLlmEndpoint = kDefaultLocalLlmEndpoint;
  String localLlmModel = kDefaultLocalLlmModel;
  String localLlmStatus = 'Not checked';
  bool isRefreshingLocalModels = false;
  List<String> availableLocalLlmModels = [];

  // Update checker
  String? latestVersion;
  DateTime? lastVersionCheck;

  bool albumAutoBackup = true;
  bool driveSyncEnabled = true;

  String? deviceId;

  // Local inference server
  bool isNodeRunning = false;
  int localNodePort = 8080;
  HttpServer? _localServer;
  String? localNodeEndpoint;

  late BackendClient backendClient;

  static Future<AppController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController._(prefs);
    controller._load();
    controller._refreshBackendClient();
    unawaited(controller.refreshLocalLlmModels());
    unawaited(controller.refreshStorageStats());
    return controller;
  }

  void _refreshBackendClient() {
    if (useRemoteNode && nodeConnected) {
      backendClient = HttpBackendClient(this);
      return;
    }
    if (localLlmEnabled) {
      backendClient = OllamaBackendClient(this);
      return;
    }
    backendClient = MockBackendClient(this);
  }

  void _load() {
    userEmail = _prefs.getString(_kUserEmail);
    authToken = _prefs.getString(_kAuthToken);
    accountServerUrl =
        _prefs.getString(_kAccountServerUrl) ?? kDefaultAccountServerUrl;
    if (accountServerUrl == 'http://127.0.0.1:3000' ||
        accountServerUrl == 'http://localhost:3000') {
      accountServerUrl = kDefaultAccountServerUrl;
    }
    if (accountServerUrl == 'https://www.zenith-app.net') {
      accountServerUrl = kDefaultAccountServerUrl;
    }
    storageDedicatedGb =
        _prefs.getDouble(_kStorageDedicatedGb) ?? kDefaultStorageReservedGb;

    final rawSavedChats = _prefs.getString(_kSavedFidusChats);
    if (rawSavedChats != null && rawSavedChats.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawSavedChats) as List<dynamic>;
        savedFidusChats = parsed
            .whereType<Map<String, dynamic>>()
            .map(FidusChatSession.fromJson)
            .toList();
      } catch (_) {
        savedFidusChats = [];
      }
    }

    final colorValue = _prefs.getInt(_kSeedColor) ?? Colors.teal.toARGB32();
    seedColor = Color(colorValue);

    darkMode = _prefs.getBool(_kDarkMode) ?? false;
    engineNode = _prefs.getString(_kEngineNode) ?? 'This device';
    engineCpuCores = _prefs.getDouble(_kEngineCpuCores) ?? 2;
    engineRamGb = _prefs.getDouble(_kEngineRamGb) ?? 4;
    enginePreferRemote = _prefs.getBool(_kEnginePreferRemote) ?? true;
    albumAutoBackup = _prefs.getBool(_kAlbumAutoBackup) ?? true;
    driveSyncEnabled = _prefs.getBool(_kDriveSyncEnabled) ?? true;
    modelId = _prefs.getString(_kModelId);
    modelLoaded = _prefs.getBool(_kModelLoaded) ?? false;
    nodeEndpoint = _prefs.getString(_kNodeEndpoint);
    nodePairingToken = _prefs.getString(_kNodePairingToken);
    nodeConnected = _prefs.getBool(_kNodeConnected) ?? false;
    useRemoteNode = _prefs.getBool(_kUseRemoteNode) ?? false;
    localLlmEnabled = _prefs.getBool(_kLocalLlmEnabled) ?? true;
    localLlmEndpoint =
        _prefs.getString(_kLocalLlmEndpoint) ?? kDefaultLocalLlmEndpoint;
    localLlmModel = _prefs.getString(_kLocalLlmModel) ?? kDefaultLocalLlmModel;
    deviceId = _prefs.getString(_kDeviceId);
    if (deviceId == null) {
      deviceId = 'zenith-${DateTime.now().millisecondsSinceEpoch}';
      unawaited(_prefs.setString(_kDeviceId, deviceId!));
    }
  }

  Future<void> _persist() async {
    if (userEmail == null) {
      await _prefs.remove(_kUserEmail);
    } else {
      await _prefs.setString(_kUserEmail, userEmail!);
    }
    if (authToken == null) {
      await _prefs.remove(_kAuthToken);
    } else {
      await _prefs.setString(_kAuthToken, authToken!);
    }
    await _prefs.setString(_kAccountServerUrl, accountServerUrl);
    await _prefs.setString(
      _kSavedFidusChats,
      jsonEncode(savedFidusChats.map((c) => c.toJson()).toList()),
    );
    await _prefs.setDouble(_kStorageDedicatedGb, storageDedicatedGb);
    await _prefs.setInt(_kSeedColor, seedColor.toARGB32());
    await _prefs.setBool(_kDarkMode, darkMode);
    await _prefs.setString(_kEngineNode, engineNode);
    await _prefs.setDouble(_kEngineCpuCores, engineCpuCores);
    await _prefs.setDouble(_kEngineRamGb, engineRamGb);
    await _prefs.setBool(_kEnginePreferRemote, enginePreferRemote);
    await _prefs.setBool(_kAlbumAutoBackup, albumAutoBackup);
    await _prefs.setBool(_kDriveSyncEnabled, driveSyncEnabled);
    if (modelId == null) {
      await _prefs.remove(_kModelId);
    } else {
      await _prefs.setString(_kModelId, modelId!);
    }
    await _prefs.setBool(_kModelLoaded, modelLoaded);
    if (nodeEndpoint == null) {
      await _prefs.remove(_kNodeEndpoint);
    } else {
      await _prefs.setString(_kNodeEndpoint, nodeEndpoint!);
    }
    if (nodePairingToken == null) {
      await _prefs.remove(_kNodePairingToken);
    } else {
      await _prefs.setString(_kNodePairingToken, nodePairingToken!);
    }
    await _prefs.setBool(_kNodeConnected, nodeConnected);
    await _prefs.setBool(_kUseRemoteNode, useRemoteNode);
    await _prefs.setBool(_kLocalLlmEnabled, localLlmEnabled);
    await _prefs.setString(_kLocalLlmEndpoint, localLlmEndpoint);
    await _prefs.setString(_kLocalLlmModel, localLlmModel);
  }

  void _save() {
    unawaited(_persist());
  }

  bool get isSignedIn => userEmail != null && authToken != null;

  void setAccountServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == accountServerUrl) return;
    accountServerUrl = trimmed;
    _save();
    notifyListeners();
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim().toLowerCase(),
      'password': password,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$accountServerUrl/api/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return data['error'] as String? ?? 'Login failed';
      }

      userEmail = data['email'] as String?;
      authToken = data['token'] as String?;
      _save();
      notifyListeners();
      return null;
    } on SocketException {
      return 'Cannot reach account server';
    } on FormatException {
      return 'Invalid server response';
    } on TimeoutException {
      return 'Account server timeout';
    } catch (e) {
      return 'Login failed: $e';
    }
  }

  Future<String?> registerAccount({
    required String email,
    required String password,
  }) async {
    final payload = <String, dynamic>{
      'email': email.trim().toLowerCase(),
      'password': password,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$accountServerUrl/api/register'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201) {
        return data['error'] as String? ?? 'Registration failed';
      }

      userEmail = data['email'] as String?;
      authToken = data['token'] as String?;
      _save();
      notifyListeners();
      return null;
    } on SocketException {
      return 'Cannot reach account server';
    } on FormatException {
      return 'Invalid server response';
    } on TimeoutException {
      return 'Account server timeout';
    } catch (e) {
      return 'Registration failed: $e';
    }
  }

  void signOut() {
    userEmail = null;
    authToken = null;
    _save();
    notifyListeners();
  }

  void setStorage(double value) {
    final maxValue = storageTotalGb > 0 ? storageTotalGb : value;
    storageDedicatedGb = value.clamp(1, maxValue).toDouble();
    _save();
    notifyListeners();
  }

  Future<void> refreshStorageStats() async {
    try {
      // Keep this Linux-first for prototype; falls back silently on unsupported platforms.
      final result = await Process.run('df', ['-k', '/']);
      if (result.exitCode != 0) return;
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return;
      final parts = lines[1].trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return;

      final totalKb = double.tryParse(parts[1]) ?? 0;
      final availableKb = double.tryParse(parts[3]) ?? 0;
      if (totalKb <= 0) return;

      storageTotalGb = totalKb / 1024 / 1024;
      storageAvailableGb = availableKb / 1024 / 1024;
      storageStatsReady = true;

      if (storageDedicatedGb > storageTotalGb) {
        storageDedicatedGb = storageTotalGb;
        _save();
      }
      notifyListeners();
    } catch (_) {
      // Keep UI usable even when stats are unavailable.
    }
  }

  void saveCurrentFidusChat(String title, List<FidusMessage> messages) {
    final trimmedTitle = title.trim().isEmpty ? 'Chat ${savedFidusChats.length + 1}' : title.trim();
    savedFidusChats.insert(
      0,
      FidusChatSession(
        title: trimmedTitle,
        createdAt: DateTime.now(),
        messages: List<FidusMessage>.from(messages),
      ),
    );
    if (savedFidusChats.length > 20) {
      savedFidusChats = savedFidusChats.take(20).toList();
    }
    _save();
    notifyListeners();
  }

  void deleteFidusChat(int index) {
    if (index < 0 || index >= savedFidusChats.length) return;
    savedFidusChats.removeAt(index);
    _save();
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    // Only check once per 6 hours
    if (lastVersionCheck != null &&
        DateTime.now().difference(lastVersionCheck!) < const Duration(hours: 6)) {
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(kGitHubApiReleasesUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String?;
        if (tagName != null) {
          // Extract version from tag (e.g., "v0.2.0" -> "0.2.0")
          final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
          latestVersion = version;
          lastVersionCheck = DateTime.now();
          notifyListeners();
        }
      }
    } catch (e) {
      // Silent fail - update check is non-critical
    }
  }

  bool get hasUpdate {
    if (latestVersion == null) return false;
    return _compareVersions(latestVersion!, kCurrentVersion) > 0;
  }

  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  void setThemeColor(Color color) {
    seedColor = color;
    _save();
    notifyListeners();
  }

  void setDarkMode(bool enabled) {
    darkMode = enabled;
    _save();
    notifyListeners();
  }

  void setEngineNode(String value) {
    engineNode = value;
    _save();
    notifyListeners();
  }

  void setEngineCpu(double value) {
    engineCpuCores = value;
    _save();
    notifyListeners();
  }

  void setEngineRam(double value) {
    engineRamGb = value;
    _save();
    notifyListeners();
  }

  void setEnginePreferRemote(bool value) {
    enginePreferRemote = value;
    _save();
    notifyListeners();
  }

  void setAlbumAutoBackup(bool value) {
    albumAutoBackup = value;
    _save();
    notifyListeners();
  }

  void setDriveSyncEnabled(bool value) {
    driveSyncEnabled = value;
    _save();
    notifyListeners();
  }

  Future<void> downloadModel(String id) async {
    modelDownloading = true;
    modelDownloadProgress = 0.0;
    notifyListeners();

    // Simulate download progress
    for (var i = 0; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      modelDownloadProgress = i / 10.0;
      notifyListeners();
    }

    modelId = id;
    modelDownloading = false;
    _save();
    notifyListeners();
  }

  Future<void> loadModel() async {
    if (modelId == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    modelLoaded = true;
    _save();
    notifyListeners();
  }

  void unloadModel() {
    modelLoaded = false;
    _save();
    notifyListeners();
  }

  Future<void> connectToNode(String endpoint, String token) async {
    nodeEndpoint = endpoint;
    nodePairingToken = token;
    nodeStatus = 'Connecting...';
    notifyListeners();

    try {
      final uri = Uri.parse('$endpoint/health');
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _setRemoteConnectionStatus(true, 'Connected');
      } else {
        _setRemoteConnectionStatus(false, 'Failed: ${response.statusCode}');
      }
    } catch (e) {
      _setRemoteConnectionStatus(
        false,
        'Failed: ${e.toString().split(':').first}',
      );
    }
  }

  void disconnectNode() {
    nodeEndpoint = null;
    nodePairingToken = null;
    nodeConnected = false;
    nodeStatus = 'Not configured';
    _refreshBackendClient();
    _save();
    notifyListeners();
  }

  void setUseRemoteNode(bool value) {
    useRemoteNode = value;
    _refreshBackendClient();
    _save();
    notifyListeners();
  }

  void setLocalLlmEnabled(bool value) {
    localLlmEnabled = value;
    _refreshBackendClient();
    _save();
    notifyListeners();
  }

  void setLocalLlmEndpoint(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == localLlmEndpoint) return;
    localLlmEndpoint = trimmed;
    _save();
  }

  void setLocalLlmModel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == localLlmModel) return;
    localLlmModel = trimmed;
    _save();
    notifyListeners();
  }

  Future<void> refreshLocalLlmModels() async {
    isRefreshingLocalModels = true;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse('$localLlmEndpoint/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final models = (data['models'] as List<dynamic>? ?? const [])
            .map((m) => (m as Map<String, dynamic>)['name'] as String?)
            .whereType<String>()
            .where((m) => m.trim().isNotEmpty)
            .where((m) => !m.toLowerCase().endsWith(':cloud'))
            .toList();

        availableLocalLlmModels = models;
        if (models.isNotEmpty && !models.contains(localLlmModel)) {
          localLlmModel = models.first;
          _save();
        }
      } else {
        availableLocalLlmModels = [];
      }
    } catch (e) {
      availableLocalLlmModels = [];
    }

    isRefreshingLocalModels = false;
    notifyListeners();
  }

  Future<void> testLocalLlmConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$localLlmEndpoint/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        await refreshLocalLlmModels();
        localLlmStatus =
            'Connected (${availableLocalLlmModels.length} model(s))';
      } else {
        localLlmStatus = 'Error ${response.statusCode}';
      }
    } catch (e) {
      localLlmStatus = 'Unreachable';
    }
    notifyListeners();
  }

  List<FidusMessage> _parseHistory(dynamic rawHistory) {
    if (rawHistory is! List) return const [];
    final messages = <FidusMessage>[];
    for (final entry in rawHistory) {
      if (entry is! Map<String, dynamic>) continue;
      final roleRaw = entry['role'] as String?;
      final content = entry['content'] as String?;
      if (content == null || content.trim().isEmpty) continue;
      final role =
          roleRaw == 'assistant' ? FidusRole.assistant : FidusRole.user;
      messages.add(FidusMessage(role: role, text: content));
    }
    return messages;
  }

  Future<String> _generateLocalLlmResponse(
    String prompt,
    List<FidusMessage> conversationHistory,
  ) {
    final localClient = OllamaBackendClient(this);
    return localClient.generateResponse(
      prompt: prompt,
      conversationHistory: conversationHistory,
    );
  }

  void _setRemoteConnectionStatus(bool connected, String status) {
    nodeConnected = connected;
    nodeStatus = status;
    _refreshBackendClient();
    _save();
    notifyListeners();
  }

  Future<void> startLocalNode() async {
    if (isNodeRunning) return;

    try {
      final router = shelf_router.Router();

      // Health check endpoint
      router.get('/health', (shelf.Request request) {
        return shelf.Response.ok(
          jsonEncode({'status': 'ok', 'model': modelId}),
          headers: {'Content-Type': 'application/json'},
        );
      });

      // Inference endpoint
      router.post('/generate', (shelf.Request request) async {
        try {
          final body = await request.readAsString();
          final data = jsonDecode(body) as Map<String, dynamic>;
          final prompt = data['prompt'] as String?;

          if (prompt == null) {
            return shelf.Response.badRequest(
              body: jsonEncode({'error': 'Missing prompt'}),
            );
          }

          final response = await _generateLocalLlmResponse(
            prompt,
            _parseHistory(data['history']),
          );

          return shelf.Response.ok(
            jsonEncode({'response': response}),
            headers: {'Content-Type': 'application/json'},
          );
        } catch (e) {
          return shelf.Response.internalServerError(
            body: jsonEncode({'error': e.toString()}),
          );
        }
      });

      final handler = const shelf.Pipeline()
          .addMiddleware(shelf.logRequests())
          .addHandler(router.call);

      _localServer = await shelf_io.serve(handler, '0.0.0.0', localNodePort);
      isNodeRunning = true;

      // Get local IP address
      final interfaces = await NetworkInterface.list();
      String? localIp;
      for (final interface in interfaces) {
        if (!interface.name.contains('lo')) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              localIp = addr.address;
              break;
            }
          }
        }
      }

      localNodeEndpoint = 'http://${localIp ?? 'localhost'}:$localNodePort';

      notifyListeners();
    } catch (e) {
      nodeStatus = 'Failed to start: $e';
      notifyListeners();
    }
  }

  Future<void> stopLocalNode() async {
    if (!isNodeRunning) return;

    await _localServer?.close(force: true);
    _localServer = null;
    isNodeRunning = false;
    localNodeEndpoint = null;

    nodeStatus = 'Stopped';
    notifyListeners();
  }

  @override
  void dispose() {
    _localServer?.close(force: true);
    super.dispose();
  }
}

class ZenithScope extends InheritedNotifier<AppController> {
  const ZenithScope({
    super.key,
    required AppController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static AppController of(BuildContext context) {
    final ZenithScope? scope =
        context.dependOnInheritedWidgetOfExactType<ZenithScope>();
    if (scope == null || scope.notifier == null) {
      throw StateError('ZenithScope is missing in widget tree.');
    }
    return scope.notifier!;
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);
    if (app.isSignedIn) {
      return const ZenithHomePage();
    }
    return const SignInPage();
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _registerMode = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final app = ZenithScope.of(context);
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final err = _registerMode
        ? await app.registerAccount(email: email, password: password)
        : await app.signIn(email: email, password: password);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zenith Account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _registerMode ? 'Create account' : 'Sign in',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your account to earn rewards for Hive Mind contributions.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Connected to $kDefaultAccountServerUrl',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Text(_registerMode ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _registerMode = !_registerMode;
                                _error = null;
                              });
                            },
                      child: Text(
                        _registerMode
                            ? 'Already have an account? Sign in'
                            : 'Need an account? Create one',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ZenithHomePage extends StatefulWidget {
  const ZenithHomePage({super.key});

  @override
  State<ZenithHomePage> createState() => _ZenithHomePageState();
}

class _ZenithHomePageState extends State<ZenithHomePage> {
  @override
  void initState() {
    super.initState();
    // Check for updates when home page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ZenithScope.of(context).checkForUpdates();
    });
  }

  Future<void> _openGitHubUpdates() async {
    final uri = Uri.parse(kGitHubReleasesUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zenith Hub'),
        actions: [
          IconButton(
            onPressed: app.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
          Badge(
            isLabelVisible: app.hasUpdate,
            label: const Text('New'),
            child: IconButton(
              onPressed: _openGitHubUpdates,
              icon: const Icon(Icons.update),
              tooltip: app.hasUpdate
                  ? 'Update available: v${app.latestVersion}'
                  : 'Check for updates on GitHub',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Signed in as ${app.userEmail}',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          Text(
            'Account server: ${app.accountServerUrl}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Text(
            'Zenith Modules',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: modules.map((module) {
              return SizedBox(
                width: 280,
                child: ModuleCard(module: module),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module});

  final ZenithModule module;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(module.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    module.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(module.description),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ModulePage(module: module),
                  ),
                );
              },
              child: const Text('Open app'),
            ),
          ],
        ),
      ),
    );
  }
}

class ModulePage extends StatelessWidget {
  const ModulePage({super.key, required this.module});

  final ZenithModule module;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(module.description),
          const SizedBox(height: 16),
          _moduleBody(context, module),
        ],
      ),
    );
  }

  Widget _moduleBody(BuildContext context, ZenithModule module) {
    switch (module.key) {
      case 'fidus':
        return const FidusPanel();
      case 'storage':
        return const StoragePanel();
      case 'theme':
        return const ThemePanel();
      case 'engine':
        return const EnginePanel();
      case 'album':
        return const AlbumPanel();
      case 'drive':
        return const DrivePanel();
      default:
        return const Text('Coming soon.');
    }
  }
}

class FidusPanel extends StatefulWidget {
  const FidusPanel({super.key});

  @override
  State<FidusPanel> createState() => _FidusPanelState();
}

class _FidusPanelState extends State<FidusPanel> {
  static const List<String> _quickPrompts = [
    'Optimize my storage setup',
    'Recommend engine settings for AI coding',
    'How should I configure photo backups?',
    'Give me a full Zenith status report',
  ];

  final TextEditingController _promptCtrl = TextEditingController();
  final TextEditingController _chatTitleCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<FidusMessage> _messages = [
    const FidusMessage(
      role: FidusRole.assistant,
      text:
          'Hi, I am Fidus. I can help plan tasks across Storage, Engine, Album, and Drive.',
    ),
  ];
  bool _isThinking = false;
  bool _showSidepanel = true;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _chatTitleCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _clearConversation() {
    setState(() {
      _messages.clear();
      _messages.add(const FidusMessage(
        role: FidusRole.assistant,
        text:
            'Hi, I am Fidus. I can help plan tasks across Storage, Engine, Album, and Drive.',
      ));
    });
  }

  Future<void> _saveCurrentChat() async {
    final app = ZenithScope.of(context);
    app.saveCurrentFidusChat(_chatTitleCtrl.text, _messages);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat saved.')),
    );
  }

  void _loadSavedChat(FidusChatSession session) {
    setState(() {
      _messages
        ..clear()
        ..addAll(session.messages);
    });
    _scrollToBottom();
  }

  Future<void> _sendPrompt() async {
    final app = ZenithScope.of(context);
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _isThinking) {
      return;
    }

    setState(() {
      _messages.add(FidusMessage(role: FidusRole.user, text: prompt));
      _isThinking = true;
      _promptCtrl.clear();
    });
    
    _scrollToBottom();

    final response = await app.backendClient.generateResponse(
      prompt: prompt,
      conversationHistory: _messages,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(FidusMessage(role: FidusRole.assistant, text: response));
      _isThinking = false;
    });
    
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);
    
    return Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left sidepanel: saved chats
          if (_showSidepanel)
            Container(
              width: 240,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saved Chats',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'New chat',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _clearConversation,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: app.savedFidusChats.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No saved chats yet',
                                style: TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: app.savedFidusChats.length,
                            itemBuilder: (context, index) {
                              final session = app.savedFidusChats[index];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: const Icon(Icons.chat_bubble_outline, size: 18),
                                title: Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${session.messages.length} msgs',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() {
                                      app.deleteFidusChat(index);
                                    });
                                  },
                                ),
                                onTap: () => _loadSavedChat(session),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          // Main chat area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Fidus the Cat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Powered by ${app.localLlmModel}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(_showSidepanel ? Icons.chevron_left : Icons.chevron_right),
                            tooltip: _showSidepanel ? 'Hide sidebar' : 'Show sidebar',
                            onPressed: () => setState(() => _showSidepanel = !_showSidepanel),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Clear conversation',
                            onPressed: _messages.length > 1 ? _clearConversation : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Helpful AI companion for planning and routing tasks across Zenith.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickPrompts
                        .map(
                          (prompt) => ActionChip(
                            label: Text(prompt),
                            onPressed: _isThinking
                                ? null
                                : () {
                                    _promptCtrl.text = prompt;
                                    _sendPrompt();
                                  },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatTitleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Chat title',
                            hintText: 'Sprint planning',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _messages.length > 1 ? _saveCurrentChat : null,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save Chat'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_isThinking ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            // Show thinking indicator
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Fidus is thinking...'),
                                ],
                              ),
                            );
                          }
                          
                          final msg = _messages[index];
                          final fromUser = msg.role == FidusRole.user;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment:
                                  fromUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 560),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: fromUser
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SelectableText(
                                  msg.text,
                                  style: TextStyle(
                                    color: fromUser
                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _promptCtrl,
                          minLines: 1,
                          maxLines: 3,
                          enabled: !_isThinking,
                          decoration: InputDecoration(
                            hintText: 'Ask Fidus to plan a task...',
                            border: const OutlineInputBorder(),
                            suffixIcon: _isThinking 
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : null,
                          ),
                          onSubmitted: (_) => _sendPrompt(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _isThinking ? null : _sendPrompt,
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StoragePanel extends StatelessWidget {
  const StoragePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reserved compute storage: ${app.storageDedicatedGb.toStringAsFixed(0)} GB',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              app.storageStatsReady
                  ? 'Disk total: ${app.storageTotalGb.toStringAsFixed(0)} GB • Available now: ${app.storageAvailableGb.toStringAsFixed(0)} GB'
                  : 'Disk stats unavailable. Click refresh to detect local capacity.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Slider(
              min: 8,
              max: app.storageStatsReady
                  ? (app.storageTotalGb < 8 ? 8 : app.storageTotalGb)
                  : 2048,
              divisions: 100,
              value: app.storageDedicatedGb,
              label: '${app.storageDedicatedGb.toStringAsFixed(0)} GB',
              onChanged: app.setStorage,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: app.refreshStorageStats,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Disk Stats'),
            ),
            const Text(
              'This value reserves local drive space for Zenith compute artifacts, model data, and generated files.',
            ),
          ],
        ),
      ),
    );
  }
}

class ThemePanel extends StatelessWidget {
  const ThemePanel({super.key});

  static const List<Color> _preset = [
    Colors.teal,
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.red,
  ];

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick a Zenith accent color:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _preset.map((color) {
                return ChoiceChip(
                  label: Text(
                    '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
                  ),
                  selected: app.seedColor.toARGB32() == color.toARGB32(),
                  onSelected: (_) => app.setThemeColor(color),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: app.darkMode,
              onChanged: app.setDarkMode,
              title: const Text('Enable dark mode'),
            ),
          ],
        ),
      ),
    );
  }
}

class EnginePanel extends StatefulWidget {
  const EnginePanel({super.key});

  @override
  State<EnginePanel> createState() => _EnginePanelState();
}

class _EnginePanelState extends State<EnginePanel> {
  static const List<String> _nodes = [
    'This device',
    'Home workstation',
    'Dedicated server',
  ];

  static const List<AIModel> _availableModels = [
    AIModel(
      id: 'phi-3-mini',
      name: 'Phi-3 Mini',
      description:
          'Fast 3.8B parameter model, great for coding and quick tasks.',
      sizeGb: 2.3,
    ),
    AIModel(
      id: 'llama-3.2-3b',
      name: 'Llama 3.2 3B',
      description: 'Balanced 3B model with strong reasoning.',
      sizeGb: 2.0,
    ),
    AIModel(
      id: 'qwen-2.5-coder-7b',
      name: 'Qwen 2.5 Coder 7B',
      description: 'Code-specialized 7B model for development tasks.',
      sizeGb: 4.7,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Model',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (app.modelId == null) ...[
              const Text('No model loaded. Choose a model to get started:'),
              const SizedBox(height: 12),
              ..._availableModels.map((model) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: app.modelDownloading
                        ? null
                        : () => app.downloadModel(model.id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(model.name),
                              Text(
                                '${model.sizeGb} GB • ${model.description}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.download),
                      ],
                    ),
                  ),
                );
              }),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _availableModels
                                  .firstWhere((m) => m.id == app.modelId)
                                  .name +
                              (app.modelLoaded ? ' (Loaded)' : ' (Downloaded)'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _availableModels
                              .firstWhere((m) => m.id == app.modelId)
                              .description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!app.modelLoaded)
                    FilledButton.icon(
                      onPressed: app.loadModel,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Load'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: app.unloadModel,
                      icon: const Icon(Icons.stop),
                      label: const Text('Unload'),
                    ),
                ],
              ),
            ],
            if (app.modelDownloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: app.modelDownloadProgress),
              const SizedBox(height: 4),
              Text(
                'Downloading ${(app.modelDownloadProgress * 100).toStringAsFixed(0)}%...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Local LLM (Ollama)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: app.localLlmEnabled,
              onChanged: app.setLocalLlmEnabled,
              title: const Text('Enable local inference'),
              subtitle:
                  const Text('Run Fidus locally via Ollama on this device.'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: app.localLlmEndpoint,
              decoration: const InputDecoration(
                labelText: 'Ollama endpoint',
                hintText: 'http://127.0.0.1:11434',
                border: OutlineInputBorder(),
              ),
              onChanged: app.setLocalLlmEndpoint,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: app.localLlmModel,
              decoration: const InputDecoration(
                labelText: 'Model name',
                hintText: 'qwen2.5-coder:7b',
                border: OutlineInputBorder(),
              ),
              onChanged: app.setLocalLlmModel,
            ),
            if (app.availableLocalLlmModels.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    app.availableLocalLlmModels.contains(app.localLlmModel)
                        ? app.localLlmModel
                        : app.availableLocalLlmModels.first,
                items: app.availableLocalLlmModels
                    .map(
                      (model) => DropdownMenuItem<String>(
                        value: model,
                        child: Text(model),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    app.setLocalLlmModel(value);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Discovered local models',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: app.isRefreshingLocalModels
                      ? null
                      : app.refreshLocalLlmModels,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Models'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: app.testLocalLlmConnection,
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('Test Local LLM'),
                ),
                const SizedBox(width: 8),
                Text(
                  app.isRefreshingLocalModels
                      ? 'Refreshing...'
                      : 'Status: ${app.localLlmStatus}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (app.modelLoaded) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Local Node Server',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (!app.isNodeRunning) ...[
                const Text(
                  'Start a local inference server to share compute with other devices.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: app.startLocalNode,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Node'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Port: ${app.localNodePort}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ] else ...[
                Card(
                  color: Colors.green.withAlpha((0.2 * 255).round()),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            const Text(
                              'Node Running',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Endpoint: ${app.localNodeEndpoint ?? "Unknown"}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: app.stopLocalNode,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Node'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Remote Node Connection',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (app.nodeEndpoint == null) ...[
              const Text(
                  'Connect to a remote Zenith node for distributed compute.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showNodePairingDialog(context, app),
                icon: const Icon(Icons.add_link),
                label: const Text('Add Remote Node'),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app.nodeEndpoint!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Status: ${app.nodeStatus}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: app.disconnectNode,
                            icon: const Icon(Icons.close),
                            tooltip: 'Disconnect',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: app.useRemoteNode,
                        onChanged:
                            app.nodeConnected ? app.setUseRemoteNode : null,
                        title: const Text('Use remote node for AI tasks'),
                        subtitle: Text(
                          app.nodeConnected
                              ? 'Fidus will send requests to this node'
                              : 'Node must be connected first',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Local Resource Limits',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: app.engineNode,
              items: _nodes
                  .map((node) => DropdownMenuItem<String>(
                        value: node,
                        child: Text(node),
                      ))
                  .toList(),
              decoration: const InputDecoration(
                labelText: 'AI execution node',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value != null) {
                  app.setEngineNode(value);
                }
              },
            ),
            const SizedBox(height: 16),
            Text('CPU cores for AI: ${app.engineCpuCores.toStringAsFixed(0)}'),
            Slider(
              min: 1,
              max: 16,
              divisions: 15,
              value: app.engineCpuCores,
              onChanged: app.setEngineCpu,
            ),
            Text('RAM for AI: ${app.engineRamGb.toStringAsFixed(0)} GB'),
            Slider(
              min: 1,
              max: 64,
              divisions: 63,
              value: app.engineRamGb,
              onChanged: app.setEngineRam,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: app.enginePreferRemote,
              onChanged: app.setEnginePreferRemote,
              title: const Text('Prefer remote node when available'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNodePairingDialog(BuildContext context, AppController app) {
    final endpointCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Remote Node'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: endpointCtrl,
                decoration: const InputDecoration(
                  labelText: 'Node Endpoint',
                  hintText: 'http://192.168.1.100:8080',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Endpoint is required';
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return 'Must start with http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: tokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'Pairing Token',
                  hintText: 'zenith-xxxxxxxx-xxxx',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Token is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop();
                await app.connectToNode(
                  endpointCtrl.text.trim(),
                  tokenCtrl.text.trim(),
                );
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class AlbumPanel extends StatelessWidget {
  const AlbumPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);

    return Card(
      child: SwitchListTile(
        value: app.albumAutoBackup,
        onChanged: app.setAlbumAutoBackup,
        title: const Text('Auto-backup photos'),
        subtitle: const Text('Backup photos into your Zenith private storage.'),
      ),
    );
  }
}

class DrivePanel extends StatelessWidget {
  const DrivePanel({super.key});

  static const List<DriveNode> _tree = [
    DriveNode.folder('Models', children: [
      DriveNode.file('qwen2.5-coder-1.5b.gguf', '1.0 GB'),
      DriveNode.file('phi-3-mini.bin', '2.3 GB'),
    ]),
    DriveNode.folder('Workspaces', children: [
      DriveNode.folder('Project-Zenith', children: [
        DriveNode.file('notes.md', '12 KB'),
        DriveNode.file('prompt-log.txt', '64 KB'),
      ]),
      DriveNode.folder('Agent-Memory', children: [
        DriveNode.file('chat-archive.json', '180 KB'),
      ]),
    ]),
    DriveNode.folder('Backups', children: [
      DriveNode.file('photos-2026-03.zip', '860 MB'),
      DriveNode.file('workspace-snapshot.tar.gz', '420 MB'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final app = ZenithScope.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: app.driveSyncEnabled,
              onChanged: app.setDriveSyncEnabled,
              title: const Text('Enable file sync'),
              subtitle: const Text('Sync files across your Zenith devices.'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Drive File Tree',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._tree.map((node) => _DriveNodeTile(node: node, depth: 0)),
          ],
        ),
      ),
    );
  }
}

class _DriveNodeTile extends StatelessWidget {
  const _DriveNodeTile({required this.node, required this.depth});

  final DriveNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final leftPad = 12.0 * depth;
    if (node.isFolder) {
      return Padding(
        padding: EdgeInsets.only(left: leftPad),
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.folder_open),
          title: Text(node.name),
          children: node.children
              .map((child) => _DriveNodeTile(node: child, depth: depth + 1))
              .toList(),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: leftPad + 16, top: 4, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(node.name)),
          if (node.sizeLabel != null)
            Text(node.sizeLabel!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class ZenithModule {
  const ZenithModule({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
  });

  final String key;
  final String name;
  final String description;
  final IconData icon;
}

enum FidusRole { user, assistant }

class FidusMessage {
  const FidusMessage({required this.role, required this.text});

  final FidusRole role;
  final String text;
}

class FidusChatSession {
  const FidusChatSession({
    required this.title,
    required this.createdAt,
    required this.messages,
  });

  factory FidusChatSession.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    return FidusChatSession(
      title: json['title'] as String? ?? 'Chat',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(
            (m) => FidusMessage(
              role: (m['role'] as String? ?? 'user') == 'assistant'
                  ? FidusRole.assistant
                  : FidusRole.user,
              text: m['text'] as String? ?? '',
            ),
          )
          .toList(),
    );
  }

  final String title;
  final DateTime createdAt;
  final List<FidusMessage> messages;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'messages': messages
          .map(
            (m) => {
              'role': m.role == FidusRole.assistant ? 'assistant' : 'user',
              'text': m.text,
            },
          )
          .toList(),
    };
  }
}

class DriveNode {
  const DriveNode._({
    required this.name,
    required this.isFolder,
    this.children = const [],
    this.sizeLabel,
  });

  const DriveNode.folder(String name, {List<DriveNode> children = const []})
      : this._(name: name, isFolder: true, children: children);

  const DriveNode.file(String name, [String? sizeLabel])
      : this._(name: name, isFolder: false, sizeLabel: sizeLabel);

  final String name;
  final bool isFolder;
  final List<DriveNode> children;
  final String? sizeLabel;
}

abstract class BackendClient {
  Future<String> generateResponse({
    required String prompt,
    required List<FidusMessage> conversationHistory,
  });
}

class MockBackendClient implements BackendClient {
  MockBackendClient(this.app);

  final AppController app;

  @override
  Future<String> generateResponse({
    required String prompt,
    required List<FidusMessage> conversationHistory,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!app.modelLoaded) {
      return 'No AI model is loaded. Please go to Engine app and load a model first.';
    }

    return _contextAwareResponse(prompt);
  }

  String _statusSummary() {
    final mode = app.darkMode ? 'dark mode' : 'light mode';
    final remotePref = app.enginePreferRemote ? 'enabled' : 'disabled';
    final album = app.albumAutoBackup ? 'enabled' : 'disabled';
    final drive = app.driveSyncEnabled ? 'enabled' : 'disabled';
    final modelName = app.modelId ?? 'none';
    return 'Status: model $modelName ${app.modelLoaded ? "loaded" : "unloaded"}, '
        'storage ${app.storageDedicatedGb.toStringAsFixed(0)} GB, '
        'engine node ${app.engineNode}, '
        '${app.engineCpuCores.toStringAsFixed(0)} CPU cores, '
        '${app.engineRamGb.toStringAsFixed(0)} GB RAM, '
        'prefer remote $remotePref, album backup $album, drive sync $drive, '
        'theme $mode.';
  }

  String _contextAwareResponse(String prompt) {
    final q = prompt.toLowerCase();
    final storageGb = app.storageDedicatedGb.toStringAsFixed(0);
    final cpu = app.engineCpuCores.toStringAsFixed(0);
    final ram = app.engineRamGb.toStringAsFixed(0);

    if (q.contains('status') ||
        q.contains('report') ||
        q.contains('overview')) {
      return _statusSummary();
    }

    if (q.contains('storage')) {
      final driveHint = app.driveSyncEnabled
          ? 'Drive sync is already enabled, good for cross-device resilience.'
          : 'Drive sync is currently off; turning it on will improve replication.';
      return 'Storage plan: you currently dedicate $storageGb GB. '
          'For active AI + backups, target at least 256 GB. $driveHint';
    }
    if (q.contains('engine') || q.contains('model') || q.contains('ai')) {
      final nodeHint = app.engineNode == 'This device'
          ? 'You are running on this device now.'
          : 'You are currently targeting ${app.engineNode}.';
      final modelHint = app.modelLoaded
          ? 'Model ${app.modelId} is loaded and ready.'
          : 'No model is loaded yet.';
      return 'Engine suggestion: $nodeHint $modelHint Current allocation is $cpu cores and '
          '$ram GB RAM. For coding assistant workloads, start around 4 cores and '
          '8 GB RAM, then scale up if responses are slow.';
    }
    if (q.contains('album') || q.contains('photo')) {
      final backupHint = app.albumAutoBackup
          ? 'Auto-backup is already enabled.'
          : 'Auto-backup is disabled right now.';
      return 'Album workflow: $backupHint Use Wi-Fi + charging windows for '
          'large uploads and keep at least 20% of your Zenith storage free.';
    }
    if (q.contains('drive') || q.contains('file')) {
      final syncHint = app.driveSyncEnabled
          ? 'Drive sync is enabled.'
          : 'Drive sync is disabled.';
      return 'Drive workflow: $syncHint Start by syncing high-value folders '
          'first and set Engine to prefer remote nodes when large indexing tasks run.';
    }
    if (q.contains('theme') || q.contains('color') || q.contains('dark')) {
      final mode = app.darkMode ? 'dark mode' : 'light mode';
      return 'Theme path: Zenith is currently in $mode with accent '
          '#${app.seedColor.toARGB32().toRadixString(16).padLeft(8, '0')}. '
          'Switch mode or accent in Theme app for your preferred control-room look.';
    }
    if (q.contains('hive')) {
      return 'Hive Mind can be designed as opt-in distributed compute with resource caps per user and signed task fragments.';
    }
    if (q.contains('code') || q.contains('implement') || q.contains('build')) {
      return 'I can help plan code implementations. For real code generation, '
          'ensure a larger model is loaded in Engine (7B+ recommended). '
          'What module or feature would you like to build?';
    }
    return 'Task understood. ${_statusSummary()} Tell me whether you want a '
        'storage-first, engine-first, or backup-first action plan.';
  }
}

class OllamaBackendClient implements BackendClient {
  OllamaBackendClient(this.app);

  final AppController app;

  static const String _systemPrompt = '''You are Fidus, a helpful AI assistant built into Project Zenith - a private cloud and AI platform.

Your personality:
- Friendly, curious, and concise
- You help users manage their Zenith modules: Storage, Engine, Album, Drive, and Chat
- You prefer practical advice over long explanations
- You understand code and can help with technical tasks

Capabilities:
- Help configure Zenith settings and modules
- Provide coding assistance and technical guidance
- Explain complex topics simply
- Plan multi-step workflows

Remember: Keep responses focused and actionable. If asked about something you don't know, admit it honestly.''';

  @override
  Future<String> generateResponse({
    required String prompt,
    required List<FidusMessage> conversationHistory,
  }) async {
    if (!app.localLlmEnabled) {
      return 'Local LLM is disabled. Enable it in Engine app.';
    }

    final uri = Uri.parse('${app.localLlmEndpoint}/api/chat');
    
    // Build message history with system prompt
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
    ];
    
    // Add conversation history
    messages.addAll(
      conversationHistory.map((m) => {
        'role': m.role == FidusRole.user ? 'user' : 'assistant',
        'content': m.text,
      }),
    );

    // Add current prompt if not already included
    if (messages.isEmpty || messages.last['role'] != 'user') {
      messages.add({'role': 'user', 'content': prompt});
    }

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': app.localLlmModel,
              'messages': messages,
              'stream': false,
              'options': {
                'temperature': 0.7,
                'top_p': 0.9,
                'top_k': 40,
              },
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = data['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String?;
        
        if (content != null && content.trim().isNotEmpty) {
          return content.trim();
        }
        return 'Local model returned an empty response. Try a different prompt.';
      }

      if (response.statusCode == 404) {
        return 'Ollama API not found at ${app.localLlmEndpoint}/api/chat.\n\n'
            'Make sure Ollama is installed and running:\n'
            '1. Install: curl -fsSL https://ollama.ai/install.sh | sh\n'
            '2. Start: ollama serve\n'
            '3. Pull model: ollama pull ${app.localLlmModel}';
      }

      return 'Local LLM error: HTTP ${response.statusCode}\n'
          'Response: ${response.body.length > 200 ? response.body.substring(0, 200) + "..." : response.body}';
    } on TimeoutException catch (_) {
      return 'Request timed out after 120 seconds. The model might be too large or slow.\n'
          'Try a smaller model like qwen2.5-coder:1.5b or llama3.2:3b.';
    } on SocketException catch (_) {
      return 'Cannot connect to Ollama at ${app.localLlmEndpoint}.\n\n'
          'Steps to fix:\n'
          '1. Check if Ollama is running: ps aux | grep ollama\n'
          '2. Start Ollama: ollama serve\n'
          '3. Verify endpoint: curl ${app.localLlmEndpoint}/api/tags';
    } catch (e) {
      return 'Unexpected error: ${e.toString()}\n\n'
          'Check that Ollama is installed and the model ${app.localLlmModel} is available.';
    }
  }
}

class HttpBackendClient implements BackendClient {
  HttpBackendClient(this.app);

  final AppController app;

  @override
  Future<String> generateResponse({
    required String prompt,
    required List<FidusMessage> conversationHistory,
  }) async {
    if (app.nodeEndpoint == null || !app.nodeConnected) {
      return 'Remote node not connected. Please configure node in Engine app.';
    }

    try {
      final uri = Uri.parse('${app.nodeEndpoint}/generate');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${app.nodePairingToken}',
            },
            body: jsonEncode({
              'prompt': prompt,
              'history': conversationHistory
                  .map((m) => {
                        'role': m.role == FidusRole.user ? 'user' : 'assistant',
                        'content': m.text,
                      })
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['response'] as String? ?? 'Empty response from node.';
      } else {
        return 'Node error: ${response.statusCode} - ${response.body}';
      }
    } catch (e) {
      return 'Failed to reach node: ${e.toString().split(':').first}';
    }
  }
}

class AIModel {
  const AIModel({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeGb,
  });

  final String id;
  final String name;
  final String description;
  final double sizeGb;
}

const List<ZenithModule> modules = [
  ZenithModule(
    key: 'fidus',
    name: 'Fidus',
    description: 'Helpful AI cat companion for coding and task orchestration.',
    icon: Icons.smart_toy_outlined,
  ),
  ZenithModule(
    key: 'storage',
    name: 'Storage',
    description: 'Allocate and manage dedicated private cloud capacity.',
    icon: Icons.storage_outlined,
  ),
  ZenithModule(
    key: 'theme',
    name: 'Theme',
    description: 'Customize colors and visual preferences for Zenith.',
    icon: Icons.palette_outlined,
  ),
  ZenithModule(
    key: 'engine',
    name: 'Engine',
    description: 'Choose where AI runs and assign hardware resources.',
    icon: Icons.memory_outlined,
  ),
  ZenithModule(
    key: 'album',
    name: 'Album',
    description: 'Photo backup module for your private storage network.',
    icon: Icons.photo_library_outlined,
  ),
  ZenithModule(
    key: 'drive',
    name: 'Drive',
    description: 'General file storage and cross-device sync module.',
    icon: Icons.folder_open_outlined,
  ),
];
