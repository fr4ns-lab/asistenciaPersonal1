import 'dart:async';
import 'dart:io' show InternetAddress, Platform;
import 'dart:math' as Math;
import 'package:asistenciapersonal1/models/last_transaction.dart';
import 'package:asistenciapersonal1/models/transaction_request.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:asistenciapersonal1/services/transaction_api.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ntp/ntp.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MarcacionAsistenciaPage extends StatefulWidget {
  const MarcacionAsistenciaPage({super.key});

  @override
  State<MarcacionAsistenciaPage> createState() =>
      _MarcacionAsistenciaPageState();
}

class _MarcacionAsistenciaPageState extends State<MarcacionAsistenciaPage>
    with WidgetsBindingObserver {
  bool _gpsActivo = true;
  Duration _serverOffset = Duration.zero;
  DateTime? _lastNtpSyncAt;
  bool _ntpInitialized = false;
  bool _internetActivo = true;
  bool _validandoServicios = true;
  Timer? _servicesTimer;
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _testOutside = false;
  bool _timeSynced = false;
  Timer? _debounceMoveCamera;
  DateTime? _lastAcceptedFixTime;
  static const double _minMovementMeters = 3;
  static const double _maxAcceptedAccuracyFallback = 25;
  bool _loading = false;
  String? _dni;
  String? _nombre;
  String? _email;
  String? _profileImage;

  DateTime? _lastMarkTime;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  bool _appBloqueada = false;
  String _mensajeBloqueo = '';
  bool _mostrandoDialogoBloqueo = false;

  int _buildActual = 0;
  int? _minBuildRequerido;
  String _versionActualTexto = '';

  Position? _position;
  bool? _inside;
  double? _accuracyMax;
  List<LatLng> _polygon = [];
  double? _distanceToCenter;
  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;

  late final TransactionApi _api;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarInfoVersionYEscucharEstado();
    _api = TransactionApi(baseUrl: 'https://apiasistencia.lasalle.edu.pe');

    _validarServiciosRequeridos();
    _servicesTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _validarServiciosRequeridos();
    });

    _startClock();
    _initUserData().then((_) async {
      if (_dni != null && _dni!.isNotEmpty) {
        await _refreshLastMark();
      }
    });
    _initLocationTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _servicesTimer?.cancel();
    _posSub?.cancel();
    _debounceMoveCamera?.cancel();
    _mapCtrl?.dispose();
    _mapCtrl = null;
    super.dispose();
  }

  bool _serviciosOk() => _gpsActivo && _internetActivo;

  String _mensajeServicios() {
    if (!_gpsActivo && !_internetActivo) {
      return 'Debes activar el GPS y conectarte a Internet para usar la aplicación.';
    }
    if (!_gpsActivo) {
      return 'Debes activar el GPS para usar la aplicación.';
    }
    if (!_internetActivo) {
      return 'Debes conectarte a Internet para usar la aplicación.';
    }
    return '';
  }

  String _userDocIdFromEmail(String email) {
    return email.toLowerCase().trim().split('@').first;
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<LastTransaction> getLastTransaction(String empCode) async {
    try {
      return await _api.getLastTransaction(empCode);
    } catch (e) {
      debugPrint('Error al obtener última transacción: $e');
      rethrow;
    }
  }

  Future<void> _validarServiciosRequeridos() async {
    final gpsActivo = await Geolocator.isLocationServiceEnabled();
    final internetActivo = await _hasInternetConnection();

    if (!mounted) return;

    setState(() {
      _gpsActivo = gpsActivo;
      _internetActivo = internetActivo;
      _validandoServicios = false;
    });
  }

  void _toggleTestLocation() {
    setState(() {
      _testOutside = !_testOutside;

      if (_testOutside) {
        // Simula que estás FUERA
        _inside = false;
        _distanceToCenter = 120; // opcional, solo visual
      } else {
        // Simula que estás DENTRO
        _inside = true;
        _distanceToCenter = 0;
      }
    });
  }

  Future<void> _showSuccessPopup() async {
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'success',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.86,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF22C55E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.35),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 62,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '¡Marcación registrada!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tu marcación se registró correctamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hora: ${_formatTime(_now)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Operación completada con éxito',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF15803D),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          'Cerrar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );

        return Transform.scale(
          scale: curved.value,
          child: Opacity(opacity: animation.value, child: child),
        );
      },
    );
  }

  Future<void> _notifyPerimeterChange(bool inside) async {
    try {
      if (inside) {
        await HapticFeedback.lightImpact();
      } else {
        await HapticFeedback.mediumImpact();
      }
    } catch (_) {}
  }

  Future<void> _cargarInfoVersionYEscucharEstado() async {
    final info = await PackageInfo.fromPlatform();
    _versionActualTexto = info.version;
    _buildActual = int.tryParse(info.buildNumber) ?? 0;

    _db.collection('settings').doc('app_status').snapshots().listen((doc) {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final bloqueadoManual = (data['bloqueado'] ?? false) as bool;
      final mensaje = (data['mensaje'] ?? '') as String;

      int? minBuild;
      if (Platform.isAndroid) {
        minBuild = (data['min_build_android'] as num?)?.toInt();
      } else if (Platform.isIOS) {
        minBuild = (data['min_build_ios'] as num?)?.toInt();
      }

      final requiereActualizacion =
          (minBuild != null && _buildActual < minBuild);

      if (!mounted) return;

      setState(() {
        _minBuildRequerido = minBuild;
        _appBloqueada = bloqueadoManual || requiereActualizacion;
        _mensajeBloqueo = _buildMensajeBloqueo(
          mensaje,
          bloqueadoManual: bloqueadoManual,
          requiereActualizacion: requiereActualizacion,
          minBuild: minBuild,
        );
      });

      if (_appBloqueada) {
        _mostrarDialogoBloqueo();
      } else {
        if (_mostrandoDialogoBloqueo) {
          Navigator.of(context, rootNavigator: true).pop();
          _mostrandoDialogoBloqueo = false;
        }
      }
    });
  }

  String _buildMensajeBloqueo(
    String mensajeFirestore, {
    required bool bloqueadoManual,
    required bool requiereActualizacion,
    int? minBuild,
  }) {
    if (requiereActualizacion && minBuild != null) {
      return 'Su versión de la aplicación está desactualizada.\n\n'
          'Versión instalada: v$_versionActualTexto (build $_buildActual)\n'
          'Versión mínima requerida: build $minBuild\n\n'
          'Por favor acérquese a la oficina de Informática del colegio para actualizar la aplicación.';
    }

    if (bloqueadoManual) {
      if (mensajeFirestore.isNotEmpty) return mensajeFirestore;
      return 'La aplicación está temporalmente deshabilitada. '
          'Por favor comuníquese con Informática del colegio.';
    }

    return '';
  }

  void _mostrarDialogoBloqueo() {
    if (_mostrandoDialogoBloqueo || !mounted) return;
    _mostrandoDialogoBloqueo = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Aplicación bloqueada'),
          content: Text(_mensajeBloqueo),
          actions: [
            TextButton(
              onPressed: () {
                _mostrandoDialogoBloqueo = false;
                Navigator.of(context, rootNavigator: true).pop();
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _syncTimeFromNTP({bool silent = false}) async {
    try {
      final ntpNow = await NTP.now();
      final deviceNow = DateTime.now();

      if (!mounted) return;

      setState(() {
        _serverOffset = ntpNow.difference(deviceNow);
        _now = deviceNow.add(_serverOffset);
        _timeSynced = true;
        _ntpInitialized = true;
        _lastNtpSyncAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('Error NTP: $e');

      if (!mounted) return;

      // No mates el reloj si ya hubo una sincronización previa
      setState(() {
        if (!_ntpInitialized) {
          _timeSynced = false;
        }
        _now = DateTime.now().add(_serverOffset);
      });

      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo revalidar la hora del servidor. Se seguirá usando la última sincronización.',
            ),
          ),
        );
      }
    }
  }

  void _startClock() {
    _syncTimeFromNTP();

    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      setState(() {
        _now = DateTime.now().add(_serverOffset);
      });

      final shouldResync =
          _lastNtpSyncAt == null ||
          DateTime.now().difference(_lastNtpSyncAt!).inMinutes >= 1;

      if (shouldResync) {
        await _syncTimeFromNTP(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.microtask(() async {
        if (!mounted) return;

        await _validarServiciosRequeridos();

        if (!mounted) return;
        await _syncTimeFromNTP(silent: true);

        if (!mounted) return;

        try {
          await _locateAndCheck();
        } catch (e) {
          debugPrint('Error al reanudar ubicación: $e');
        }
      });
    }
  }

  Future<void> _initUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;

    final docId = _userDocIdFromEmail(email);
    final doc = await _db.collection('users').doc(docId).get();
    final data = doc.data();

    if (!mounted) return;

    setState(() {
      _email = email;
      _nombre = data?['name'] ?? user.displayName;
      _dni = data?['dni'];

      final photoFromDb = data?['photoUrl'] as String?;
      _profileImage =
          (photoFromDb != null && photoFromDb.trim().isNotEmpty)
              ? photoFromDb.trim()
              : user.photoURL;
    });
  }

  Future<void> _initLocationTracking() async {
    await _loadGeofence();
    await _locateAndCheck();
    _listenPosition();
  }

  LatLng? _parseLatLngString(String s) {
    final re = RegExp(
      r'([\d\.]+)\D*([NSEW])\s*,\s*([\d\.]+)\D*([NSEW])',
      caseSensitive: false,
    );
    final m = re.firstMatch(s);
    if (m == null) return null;

    double lat = double.parse(m.group(1)!);
    String latH = m.group(2)!.toUpperCase();
    double lng = double.parse(m.group(3)!);
    String lngH = m.group(4)!.toUpperCase();

    if (latH == 'S') lat = -lat;
    if (lngH == 'W') lng = -lng;

    return LatLng(lat, lng);
  }

  Future<void> _loadGeofence() async {
    try {
      final doc = await _db.doc('settings/geofence').get();
      if (!doc.exists) {
        debugPrint('No existe settings/geofence');
        return;
      }

      final data = doc.data();
      if (data == null) return;

      final raw = data['points'];
      if (raw == null || raw is! List) {
        debugPrint('El campo "points" no existe o no es una lista');
        return;
      }

      final pts = <LatLng>[];
      for (final p in raw) {
        if (p is GeoPoint) {
          pts.add(LatLng(p.latitude, p.longitude));
          continue;
        }

        if (p is Map) {
          if (p['lat'] != null && p['lng'] != null) {
            final lat = (p['lat'] as num).toDouble();
            final lng = (p['lng'] as num).toDouble();
            pts.add(LatLng(lat, lng));
            continue;
          }

          if (p['geopoint'] is GeoPoint) {
            final g = p['geopoint'] as GeoPoint;
            pts.add(LatLng(g.latitude, g.longitude));
            continue;
          }
        }

        if (p is String) {
          final parsed = _parseLatLngString(p);
          if (parsed != null) {
            pts.add(parsed);
            continue;
          }
        }

        debugPrint('Tipo no soportado en points: ${p.runtimeType} -> $p');
      }

      _accuracyMax = (data['accuracyMax'] as num?)?.toDouble();
      _polygon = pts;

      if (!mounted) return;

      setState(() {});

      await Future.delayed(const Duration(milliseconds: 250));
      await _fitMapToPolygon();
    } catch (e) {
      debugPrint('Error al cargar geofence: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error Firestore (geocerca): $e')),
        );
      }
    }
  }

  double _distanceToPolygon(Position pos) {
    if (_polygon.isEmpty) return 0;

    double minDist = double.infinity;
    for (final v in _polygon) {
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        v.latitude,
        v.longitude,
      );
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  Future<bool> _ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa los servicios de ubicación.')),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado.')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permiso denegado permanentemente. Ve a Ajustes para habilitarlo.',
            ),
          ),
        );
      }
      return false;
    }

    return true;
  }

  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    if (poly.length < 3) return false;
    bool inside = false;

    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final px = p.longitude, py = p.latitude;

      final intersects =
          ((yi > py) != (yj > py)) &&
          (px <
              (xj - xi) * (py - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);

      if (intersects) inside = !inside;
    }

    return inside;
  }

  double _clamp(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  void _moveCameraSoft(Position pos) {
    if (_mapCtrl == null) return;

    _debounceMoveCamera?.cancel();
    _debounceMoveCamera = Timer(const Duration(milliseconds: 350), () {
      _mapCtrl?.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    });
  }

  Future<void> _fitMapToPolygon() async {
    if (_mapCtrl == null || _polygon.isEmpty) return;

    double minLat = _polygon.first.latitude;
    double maxLat = _polygon.first.latitude;
    double minLng = _polygon.first.longitude;
    double maxLng = _polygon.first.longitude;

    for (final p in _polygon) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _mapCtrl!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<Position?> _getBestAccuratePosition() async {
    final ok = await _ensurePermissions();
    if (!ok) return null;

    Position? best;

    Future<void> tryRead({
      required LocationAccuracy accuracy,
      Duration? timeLimit,
    }) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: accuracy,
          timeLimit: timeLimit,
        );

        debugPrint('Lectura GPS -> ${pos.accuracy} m');

        if (best == null || pos.accuracy < best!.accuracy) {
          best = pos;
        }
      } catch (_) {}
    }

    // 🔥 SOLO intentos rápidos (sin delay)
    await tryRead(
      accuracy: LocationAccuracy.bestForNavigation,
      timeLimit: const Duration(seconds: 5),
    );

    if (best != null &&
        _accuracyMax != null &&
        best!.accuracy > _accuracyMax!) {
      await tryRead(
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    }

    return best;
  }

  Future<void> _locateAndCheck() async {
    final pos = await _getBestAccuratePosition();
    if (pos == null) return;

    bool nowInside = false;
    if (_polygon.isNotEmpty) {
      nowInside = _pointInPolygon(
        LatLng(pos.latitude, pos.longitude),
        _polygon,
      );
    }

    final prevInside = _inside;
    _position = pos;
    _inside = nowInside;
    _lastAcceptedFixTime = DateTime.now();

    if (_polygon.isNotEmpty) {
      _distanceToCenter = _inside == true ? 0 : _distanceToPolygon(pos);
    }

    if (!mounted) return;

    setState(() {});

    if (prevInside != null && prevInside != nowInside) {
      _notifyPerimeterChange(nowInside);
    }

    _moveCameraSoft(pos);
  }

  void _listenPosition() {
    _posSub?.cancel();

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      final maxAllowed = _accuracyMax ?? _maxAcceptedAccuracyFallback;

      // 1. descartar lecturas imprecisas
      if (pos.accuracy > maxAllowed) {
        return;
      }

      // 2. descartar micro saltos falsos
      if (_position != null) {
        final dist = Geolocator.distanceBetween(
          _position!.latitude,
          _position!.longitude,
          pos.latitude,
          pos.longitude,
        );

        if (dist < _minMovementMeters && pos.accuracy >= _position!.accuracy) {
          return;
        }
      }

      final nowInside =
          _polygon.isNotEmpty
              ? _pointInPolygon(LatLng(pos.latitude, pos.longitude), _polygon)
              : false;

      final changed = (_inside != null && _inside != nowInside);

      _position = pos;
      _inside = nowInside;
      _lastAcceptedFixTime = DateTime.now();

      if (_polygon.isNotEmpty) {
        _distanceToCenter = _inside == true ? 0 : _distanceToPolygon(pos);
      }

      if (!mounted) return;

      setState(() {});

      if (changed) {
        _notifyPerimeterChange(nowInside);
      }

      _moveCameraSoft(pos);
    });
  }

  Future<void> _enviarMarcacionBiotime({
    required String empCode,
    required double lat,
    required double lng,
  }) async {
    final tx = TransactionRequest(
      empCode: empCode,
      punchTime: null,
      longitude: lng,
      latitude: lat,
      gpsLocation: 'Lat: $lat, Lng: $lng',
      mobile: null,
    );

    await _api.sendTransaction(tx);
  }

  Future<void> _refreshLastMark() async {
    try {
      final lastTx = await getLastTransaction(_dni!);
      if (!mounted) return;

      setState(() {
        _lastMarkTime = lastTx.data.punchTime;
      });
    } catch (e) {
      debugPrint("Error refrescando última marcación: $e");
    }
  }

  Future<void> _handleMark() async {
    if (!_serviciosOk()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mensajeServicios())));
      }
      return;
    }

    if (_appBloqueada) {
      _mostrarDialogoBloqueo();
      return;
    }
    if (!_timeSynced) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se puede marcar sin sincronizar la hora NTP.'),
          ),
        );
      }
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay sesión activa. Vuelve a iniciar sesión con tu cuenta institucional.',
            ),
          ),
        );
      }
      return;
    }

    if (_dni == null || _dni!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tu cuenta no tiene DNI asociado. Comunícate con el administrador.',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _locateAndCheck();

      final pos = _position;
      final isInside = _inside ?? false;
      final maxAllowed = _accuracyMax ?? _maxAcceptedAccuracyFallback;
      final now = DateTime.now();
      final isRecentFix =
          _lastAcceptedFixTime != null &&
          now.difference(_lastAcceptedFixTime!).inSeconds <= 15;

      if (!isRecentFix) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tu ubicación no está actualizada. Espera unos segundos o pulsa actualizar ubicación.',
            ),
          ),
        );
        return;
      }

      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo obtener tu ubicación actual.'),
          ),
        );
        return;
      }

      if (pos.accuracy > maxAllowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            content: Text(
              'La ubicación aún no es suficientemente precisa (${pos.accuracy.toStringAsFixed(1)} m). Intenta nuevamente en unos segundos.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
        return;
      }

      if (pos == null || !isInside) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Estás fuera del área permitida.\n'
                'Distancia aprox. al perímetro: '
                '${_distanceToCenter?.toStringAsFixed(1) ?? '-'} m',
              ),
            ),
          );
        }
        return;
      }

      await _enviarMarcacionBiotime(
        empCode: _dni!,
        lat: pos.latitude,
        lng: pos.longitude,
      );

      await _refreshLastMark();

      if (!mounted) return;

      await _showSuccessPopup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar la marcación: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatTwo(int n) => n.toString().padLeft(2, '0');

  String _formatTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'p. m.' : 'a. m.';
    return '${_formatTwo(hour12)}:${_formatTwo(d.minute)}:${_formatTwo(d.second)} $period';
  }

  String _formatDateFull(DateTime d) {
    const dias = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    final weekday = dias[d.weekday - 1];
    final month = meses[d.month - 1];
    return '${_capitalize(weekday)}, ${d.day} de $month';
  }

  String _formatSimpleDate(DateTime d) {
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${d.day} de ${meses[d.month - 1]}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _locationStatusTitle() {
    if (_inside == null) return 'Verificando ubicación';
    return _inside! ? 'Dentro del perímetro' : 'Fuera del perímetro';
  }

  String _locationStatusSubtitle() {
    final pos = _position;
    if (pos == null) return 'Esperando señal GPS';
    final precision = 'GPS ±${pos.accuracy.toStringAsFixed(0)} m';

    if (_inside == true) {
      return 'Ubicación validada automáticamente · $precision';
    }
    if (_distanceToCenter != null) {
      return 'Aprox. ${_distanceToCenter!.toStringAsFixed(1)} m del perímetro · $precision';
    }
    return precision;
  }

  double _locationProgressValue() {
    final pos = _position;
    if (pos == null) return 0.2;
    if (_accuracyMax == null || _accuracyMax == 0) {
      return _inside == true ? 1 : 0.35;
    }

    final ratio = 1 - (pos.accuracy / _accuracyMax!).clamp(0.0, 1.0);
    return ratio.toDouble().clamp(0.08, 1.0);
  }

  Color _statusColor(BuildContext context) {
    if (_inside == null) return Colors.orange;
    return _inside! ? Colors.green : Theme.of(context).colorScheme.error;
  }

  IconData _statusIcon() {
    if (_inside == null) return Icons.gps_not_fixed_rounded;
    return _inside! ? Icons.verified_user_rounded : Icons.location_off_rounded;
  }

  String _buttonLabel() {
    if (_loading) return 'Registrando...';
    return 'Registrar marcación';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pos = _position;

    final statusColor = _statusColor(context);

    return Scaffold(
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     final maxAllowed = _accuracyMax ?? _maxAcceptedAccuracyFallback;

      //     debugPrint("Accuracy actual: ${_position?.accuracy}");
      //     debugPrint("Max permitido: $maxAllowed");
      //   },
      //   // onPressed: _toggleTestLocation,
      //   backgroundColor: _testOutside ? Colors.red : Colors.green,
      //   child: Icon(_testOutside ? Icons.location_off : Icons.location_on),
      // ),
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        title: Text(
          'SalleTime',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: IconButton(
              onPressed: () async {
                await AuthService.instance.signOut(context);
              },
              icon: Icon(Icons.output_sharp, color: const Color(0xFF2563EB)),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Container(
                //   padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                //   child: Row(
                //     children: [
                //       Expanded(
                //         child: Text(
                //           'Registro de marcación',
                //           style: theme.textTheme.headlineSmall?.copyWith(
                //             fontWeight: FontWeight.w800,
                //             color: const Color(0xFF0F172A),
                //           ),
                //         ),
                //       ),
                //       // Container(
                //       //   decoration: BoxDecoration(
                //       //     color: Colors.white,
                //       //     borderRadius: BorderRadius.circular(16),
                //       //     border: Border.all(color: const Color(0xFFE2E8F0)),
                //       //   ),
                //       //   child: IconButton(
                //       //     onPressed:
                //       //         _appBloqueada ? _mostrarDialogoBloqueo : null,
                //       //     icon: Icon(
                //       //       Icons.settings_outlined,
                //       //       color:
                //       //           _appBloqueada
                //       //               ? const Color(0xFF2563EB)
                //       //               : const Color(0xFF64748B),
                //       //     ),
                //       //   ),
                //       // ),
                //       Container(
                //         decoration: BoxDecoration(
                //           color: Colors.white,
                //           borderRadius: BorderRadius.circular(16),
                //           border: Border.all(color: const Color(0xFFE2E8F0)),
                //         ),
                //         child: IconButton(
                //           onPressed: () async {
                //             await AuthService.instance.signOut(context);
                //           },
                //           icon: Icon(
                //             Icons.output_sharp,
                //             color: const Color(0xFF2563EB),
                //           ),
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileCard(
                          nombre: _nombre ?? 'Usuario',
                          email: _email ?? 'Sin correo',
                          dni: _dni,
                          profileImage: _profileImage,
                          initials: _initialsFromName(_nombre),
                        ),
                        const SizedBox(height: 18),

                        // Container(
                        //   height: 260,
                        //   decoration: BoxDecoration(
                        //     borderRadius: BorderRadius.circular(20),
                        //     border: Border.all(color: const Color(0xFFE2E8F0)),
                        //   ),
                        //   clipBehavior: Clip.hardEdge,
                        //   child: GoogleMap(
                        //     initialCameraPosition: CameraPosition(
                        //       target:
                        //           _polygon.isNotEmpty
                        //               ? _polygon.first
                        //               : const LatLng(
                        //                 -16.3989,
                        //                 -71.5369,
                        //               ), // fallback Arequipa
                        //       zoom: 26,
                        //     ),

                        //     onMapCreated: (controller) async {
                        //       _mapCtrl = controller;

                        //       await Future.delayed(
                        //         const Duration(milliseconds: 300),
                        //       );

                        //       await _fitMapToPolygon();

                        //       if (_position != null) {
                        //         _moveCameraSoft(_position!);
                        //       }
                        //     },

                        //     myLocationEnabled: true,
                        //     myLocationButtonEnabled: true,
                        //     zoomControlsEnabled: false,

                        //     polygons:
                        //         _polygon.isEmpty
                        //             ? {}
                        //             : {
                        //               Polygon(
                        //                 polygonId: const PolygonId('geofence'),
                        //                 points: _polygon,
                        //                 strokeWidth: 3,
                        //                 strokeColor: Colors.blue,
                        //                 fillColor: Colors.blue.withOpacity(
                        //                   0.15,
                        //                 ),
                        //               ),
                        //             },

                        //     markers: {
                        //       if (_position != null)
                        //         Marker(
                        //           markerId: const MarkerId('user'),
                        //           position: LatLng(
                        //             _position!.latitude,
                        //             _position!.longitude,
                        //           ),
                        //           infoWindow: const InfoWindow(
                        //             title: 'Tu ubicación',
                        //           ),
                        //         ),
                        //     },
                        //   ),
                        // ),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hora actual',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF2563EB),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (!_validandoServicios && !_serviciosOk()) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.wifi_off_rounded,
                                        color: Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _mensajeServicios(),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: const Color(0xFF991B1B),
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _timeSynced ? _formatTime(_now) : '--:--:--',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _timeSynced
                                    ? _formatDateFull(_now)
                                    : 'Sin sincronización con servidor',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          scale: _inside == null ? 1.0 : 1.015,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeOut,
                            child: _StatusLocationCard(
                              key: ValueKey(_inside),
                              color: statusColor,
                              icon: _statusIcon(),
                              title: _locationStatusTitle(),
                              badge:
                                  pos != null
                                      ? 'GPS ±${pos.accuracy.toStringAsFixed(0)} m'
                                      : 'GPS --',
                              subtitle: _locationStatusSubtitle(),
                              progress: _locationProgressValue(),
                              onRefresh: _locateAndCheck,
                              helperText:
                                  'Uso de emergencia: actualiza tu ubicación si el seguimiento automático falla.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _PreviousCheckCard(
                          lastMarkTime: _lastMarkTime,
                          formatTime: _formatTime,
                          formatDate: _formatSimpleDate,
                        ),
                        // const SizedBox(height: 18),
                        // _NextMarkCard(nextType: _friendlyNextType(nextType)),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed:
                              (_loading ||
                                      !_timeSynced ||
                                      _inside != true ||
                                      _appBloqueada ||
                                      !_serviciosOk() ||
                                      _validandoServicios)
                                  ? null
                                  : _handleMark,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _inside == true
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF94A3B8),
                            disabledBackgroundColor: const Color(0xFFCBD5E1),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white70,
                            elevation: _inside == true ? 8 : 0,
                            shadowColor: const Color(0x552563EB),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_loading)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  _inside == true
                                      ? Icons.fingerprint_rounded
                                      : Icons.location_off_rounded,
                                  size: 26,
                                ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _loading
                                      ? 'Registrando...'
                                      : (_inside == true
                                          ? 'Registrar marcación'
                                          : 'Fuera del perímetro'),
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          !_timeSynced
                              ? 'No se puede marcar mientras no se sincronice la hora del servidor.'
                              : (_inside == true
                                  ? 'Tu ubicación es válida. Ya puedes realizar la marcación.'
                                  : 'Estás fuera del perímetro permitido. El botón de marcación está deshabilitado hasta que vuelvas a ingresar.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                _inside == true
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_appBloqueada) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Aplicación bloqueada',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF991B1B),
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _mensajeBloqueo,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF7F1D1D),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_appBloqueada || (!_validandoServicios && !_serviciosOk()))
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(color: Colors.black.withOpacity(0.12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.nombre,
    required this.email,
    required this.dni,
    required this.profileImage,
    required this.initials,
  });

  final String nombre;
  final String email;
  final String? dni;
  final String? profileImage;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCEAFE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF2563EB),
                    width: 2.5,
                  ),
                  gradient:
                      (profileImage == null || profileImage!.trim().isEmpty)
                          ? const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                          : null,
                  image:
                      (profileImage != null && profileImage!.trim().isNotEmpty)
                          ? DecorationImage(
                            image: NetworkImage(profileImage!),
                            fit: BoxFit.cover,
                          )
                          : null,
                ),
                child:
                    (profileImage == null || profileImage!.trim().isEmpty)
                        ? Center(
                          child: Text(
                            initials,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                        : null,
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (dni != null && dni!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'DNI: $dni',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLocationCard extends StatelessWidget {
  const _StatusLocationCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.progress,
    required this.onRefresh,
    required this.helperText,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String badge;
  final String subtitle;
  final double progress;
  final VoidCallback onRefresh;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.26), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    color: color,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: progress,
                          backgroundColor: const Color(0xFFE5E7EB),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Precisión',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Margen permitido',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  helperText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: onRefresh,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: const Text(
                  'Actualizar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviousCheckCard extends StatelessWidget {
  const _PreviousCheckCard({
    required this.lastMarkTime,
    required this.formatTime,
    required this.formatDate,
  });

  final DateTime? lastMarkTime;
  final String Function(DateTime) formatTime;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMark = lastMarkTime != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCEAFE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Última marcación',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hasMark ? formatTime(lastMarkTime!) : '--:--:--',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasMark
                      ? 'Registrada el ${formatDate(lastMarkTime!)}'
                      : 'Aún no hay registros disponibles.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

// class _NextMarkCard extends StatelessWidget {
//   const _NextMarkCard({required this.nextType});

//   final String nextType;

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     return Container(
//       padding: const EdgeInsets.all(18),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: const Color(0xFFDCEAFE)),
//         boxShadow: const [
//           BoxShadow(
//             color: Color(0x120F172A),
//             blurRadius: 18,
//             offset: Offset(0, 8),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 54,
//             height: 54,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               border: Border.all(color: const Color(0xFFCBD5E1), width: 1.4),
//             ),
//             child: const Icon(
//               Icons.fingerprint_rounded,
//               color: Color(0xFF0F172A),
//               size: 28,
//             ),
//           ),
//           const SizedBox(width: 14),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Próxima marcación',
//                   style: theme.textTheme.labelLarge?.copyWith(
//                     color: const Color(0xFF64748B),
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   nextType,
//                   style: theme.textTheme.titleLarge?.copyWith(
//                     color: const Color(0xFF0F172A),
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   'El sistema alterna automáticamente entre entrada y salida según tu último registro.',
//                   style: theme.textTheme.bodySmall?.copyWith(
//                     color: const Color(0xFF64748B),
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
