import 'dart:async';
import 'dart:io' show Platform;

import 'package:asistenciapersonal1/models/transaction_request.dart';
import 'package:asistenciapersonal1/services/transaction_api.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

class _MarcacionAsistenciaPageState extends State<MarcacionAsistenciaPage> {
  // ----------- Firebase / usuario -----------
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  Duration? _serverOffset; // diferencia entre hora NTP y hora del dispositivo

  bool _loading = false;
  String? _dni;
  String? _nombre;
  String? _email;
  String _lastMarkType = 'ninguna'; // entrada / salida / ninguna
  DateTime? _lastMarkTime;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // ---- Control de bloqueo remoto ----
  bool _appBloqueada = false;
  String _mensajeBloqueo = '';
  bool _mostrandoDialogoBloqueo = false;

  // ---- Control de versión ----
  int _buildActual = 0;
  int? _minBuildRequerido;
  String _versionActualTexto = '';

  // ----------- Geolocalización / geocerca -----------
  Position? _position;
  bool? _inside; // null = sin calcular aún
  double? _accuracyMax; // metros máximos aceptables
  List<LatLng> _polygon = [];
  double? _distanceToCenter; // para mostrar "distancia al colegio" aprox.
  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;

  // ----------- API Biotime -----------
  late final TransactionApi _api;

  @override
  void initState() {
    super.initState();
    _cargarInfoVersionYEscucharEstado();
    _api = TransactionApi(baseUrl: 'https://apiasistencia.lasalle.edu.pe');

    _startClock();
    _initUserData();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _posSub?.cancel();

    _mapCtrl?.dispose();
    _mapCtrl = null;

    super.dispose();
  }

  // ================= BLOQUEO POR VERSIÓN / ESTADO REMOTO =================

  Future<void> _cargarInfoVersionYEscucharEstado() async {
    // 1. Obtener info del app
    final info = await PackageInfo.fromPlatform();
    _versionActualTexto = info.version; // ej: "1.0.1"
    _buildActual = int.tryParse(info.buildNumber) ?? 0; // ej: 4

    // 2. Escuchar el documento de configuración
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
    // Si está bloqueado por versión desactualizada
    if (requiereActualizacion && minBuild != null) {
      return 'Su versión de la aplicación está desactualizada.\n\n'
          'Versión instalada: v$_versionActualTexto (build $_buildActual)\n'
          'Versión mínima requerida: build $minBuild\n\n'
          'Por favor acérquese a la oficina de Informática del colegio para actualizar la aplicación.';
    }

    // Si está bloqueado manualmente por Informática
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
          title: const Text(
            'Aplicación bloqueada',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(_mensajeBloqueo),
          actions: [
            TextButton(
              onPressed: () {
                _mostrandoDialogoBloqueo = false;
                Navigator.of(context, rootNavigator: true).pop();
                // Opcional: SystemNavigator.pop();
              },
              child: const Text(
                'Aceptar',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // ================= RELOJ =================

  Future<void> _syncTimeFromNTP() async {
    try {
      final ntpNow = await NTP.now();
      final deviceNow = DateTime.now();
      final offset = ntpNow.difference(deviceNow);

      if (!mounted) return;
      setState(() {
        _serverOffset = offset;
        _now = ntpNow;
      });
    } catch (e) {
      debugPrint('Error NTP: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo sincronizar hora con internet. Usando hora del dispositivo.',
            ),
          ),
        );
      }
    }
  }

  void _startClock() {
    _syncTimeFromNTP();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final deviceNow = DateTime.now();
      final displayNow =
          _serverOffset != null ? deviceNow.add(_serverOffset!) : deviceNow;

      setState(() {
        _now = displayNow;
      });
    });
  }

  // ================= DATOS DE USUARIO =================

  Future<void> _initUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();

    if (!mounted) return;

    setState(() {
      _email = user.email;
      _nombre = user.displayName ?? data?['name'];
      _dni = data?['dni'];

      final lastType = data?['lastMarkType'] as String?;
      final lastTimeTS = data?['lastMarkTime'];

      if (lastType != null && lastTimeTS is Timestamp) {
        _lastMarkType = lastType;
        _lastMarkTime = lastTimeTS.toDate();
      }
    });
  }

  String _nextMarkTypeFor(DateTime now) {
    if (_lastMarkTime == null) {
      return 'entrada';
    }

    final sameDay =
        _lastMarkTime!.year == now.year &&
        _lastMarkTime!.month == now.month &&
        _lastMarkTime!.day == now.day;

    if (!sameDay) {
      return 'entrada';
    }

    return _lastMarkType == 'entrada' ? 'salida' : 'entrada';
  }

  // ================= GEOFERNCE / UBICACIÓN =================

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

      if (_mapCtrl != null && _polygon.isNotEmpty) {
        double minLat = _polygon.first.latitude,
            maxLat = _polygon.first.latitude;
        double minLng = _polygon.first.longitude,
            maxLng = _polygon.first.longitude;

        for (final q in _polygon) {
          if (q.latitude < minLat) minLat = q.latitude;
          if (q.latitude > maxLat) maxLat = q.latitude;
          if (q.longitude < minLng) minLng = q.longitude;
          if (q.longitude > maxLng) maxLng = q.longitude;
        }

        final bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );

        try {
          if (!mounted || _mapCtrl == null) return;
          await _mapCtrl!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 80),
          );
        } catch (e) {
          debugPrint(
            'No se pudo animar cámara (mapa dispose?) en _loadGeofence: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('Error al cargar geofence: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error Firestore (geofence): $e')),
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

  Future<void> _locateAndCheck() async {
    final ok = await _ensurePermissions();
    if (!ok) return;

    var pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    if (_accuracyMax != null && pos.accuracy > _accuracyMax!) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {}
    }

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

    if (_polygon.isNotEmpty) {
      if (_inside == true) {
        _distanceToCenter = 0;
      } else {
        _distanceToCenter = _distanceToPolygon(pos);
      }
    }

    if (_mapCtrl != null) {
      try {
        if (!mounted || _mapCtrl == null) return;
        await _mapCtrl!.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      } catch (e) {
        debugPrint('No se pudo animar cámara en _locateAndCheck: $e');
      }
    }

    if (!mounted) return;

    setState(() {});
    if (prevInside != null && prevInside != nowInside) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowInside ? 'Entraste al perímetro.' : 'Saliste del perímetro.',
          ),
        ),
      );
    }
  }

  void _listenPosition() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final nowInside =
          _polygon.isNotEmpty
              ? _pointInPolygon(LatLng(pos.latitude, pos.longitude), _polygon)
              : false;

      final changed = (_inside != null && _inside != nowInside);
      _position = pos;
      _inside = nowInside;

      if (_polygon.isNotEmpty) {
        if (_inside == true) {
          _distanceToCenter = 0;
        } else {
          _distanceToCenter = _distanceToPolygon(pos);
        }
      }

      if (!mounted) return;

      setState(() {});
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nowInside ? 'Entraste al perímetro.' : 'Saliste del perímetro.',
            ),
          ),
        );
      }

      if (_mapCtrl != null) {
        try {
          _mapCtrl!.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          );
        } catch (e) {
          debugPrint('No se pudo animar cámara en _listenPosition: $e');
        }
      }
    });
  }

  // ================= API BIOTIME =================

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

  // ================= LÓGICA DE MARCACIÓN =================

  Future<void> _handleMark() async {
    // 👉 Seguridad extra: si está bloqueada, no marcamos
    if (_appBloqueada) {
      _mostrarDialogoBloqueo();
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
      final nowDevice = DateTime.now();
      final now =
          _serverOffset != null ? nowDevice.add(_serverOffset!) : nowDevice;

      final nextType = _nextMarkTypeFor(now);

      if (_lastMarkTime != null) {
        final sameDay =
            _lastMarkTime!.year == now.year &&
            _lastMarkTime!.month == now.month &&
            _lastMarkTime!.day == now.day;

        if (sameDay && _lastMarkType == 'salida') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ya registraste ENTRADA y SALIDA hoy. No se permiten más marcaciones.',
                ),
              ),
            );
          }
          return;
        }
      }

      await _locateAndCheck();

      final pos = _position;
      final isInside = _inside ?? false;

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

      final uid = user.uid;
      await _db.collection('users').doc(uid).update({
        'lastMarkType': nextType,
        'lastMarkTime': Timestamp.fromDate(now),
      });

      if (!mounted) return;

      setState(() {
        _lastMarkType = nextType;
        _lastMarkTime = now;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marcación de $nextType registrada correctamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  // ================= HELPERS DE UI =================

  String _formatTwo(int n) => n.toString().padLeft(2, '0');

  String _friendlyNextType(String type) {
    if (type == 'entrada') return 'ENTRADA';
    if (type == 'salida') return 'SALIDA';
    return type.toUpperCase();
  }

  String _formatDate(DateTime d) {
    return '${_formatTwo(d.day)}/${_formatTwo(d.month)}/${d.year}';
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pos = _position;
    final deviceNow = DateTime.now();
    final logicalNow =
        _serverOffset != null ? deviceNow.add(_serverOffset!) : deviceNow;
    final nextType = _nextMarkTypeFor(logicalNow);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de asistencia'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // -------- CONTENIDO NORMAL --------
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceVariant.withOpacity(0.2),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ===== CARD USUARIO + HORA =====
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 26,
                                    child: Text(
                                      (_nombre ?? 'U').isNotEmpty
                                          ? (_nombre ?? 'U')[0].toUpperCase()
                                          : 'U',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_nombre != null)
                                          Text(
                                            _nombre!,
                                            style: textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        if (_email != null)
                                          Text(
                                            _email!,
                                            style: textTheme.bodySmall,
                                          ),
                                        if (_dni != null)
                                          Text(
                                            'DNI: $_dni',
                                            style: textTheme.bodySmall,
                                          ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.access_time,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Hora actual:',
                                              style: textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${_formatTwo(_now.hour)}:'
                                              '${_formatTwo(_now.minute)}:'
                                              '${_formatTwo(_now.second)}',
                                              style: textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            Text(
                                              _formatDate(_now),
                                              style: textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (_lastMarkTime != null)
                                          Text(
                                            'Última marcación: '
                                            '${_lastMarkType} a las '
                                            '${_formatTwo(_lastMarkTime!.hour)}:'
                                            '${_formatTwo(_lastMarkTime!.minute)}',
                                            style: textTheme.bodySmall,
                                          )
                                        else
                                          Text(
                                            'Sin marcaciones registradas hoy.',
                                            style: textTheme.bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ===== CARD PRÓXIMA MARCACIÓN =====
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.fingerprint,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Próxima marcación',
                                          style: textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _friendlyNextType(nextType),
                                          style: textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Se alterna automáticamente entre ENTRADA y SALIDA según tu última marca.',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ===== CARD ESTADO DE UBICACIÓN =====
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.my_location, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Estado de ubicación',
                                        style: textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Chip(
                                          avatar: Icon(
                                            _inside == null
                                                ? Icons.help_outline
                                                : (_inside!
                                                    ? Icons.check_circle
                                                    : Icons
                                                        .warning_amber_rounded),
                                            size: 18,
                                          ),
                                          label: Text(
                                            _inside == null
                                                ? 'Sin estado'
                                                : (_inside!
                                                    ? 'Dentro del perímetro'
                                                    : 'Fuera del perímetro'),
                                            style: const TextStyle(
                                              color: Colors.black,
                                            ),
                                          ),
                                          backgroundColor:
                                              _inside == null
                                                  ? Colors.grey.shade300
                                                  : (_inside!
                                                      ? Colors.green.shade200
                                                      : Colors.red.shade200),
                                        ),
                                        if (pos != null)
                                          Chip(
                                            avatar: const Icon(
                                              Icons.gps_fixed,
                                              size: 18,
                                            ),
                                            label: Text(
                                              'Precisión: '
                                              '${pos.accuracy.toStringAsFixed(1)} m'
                                              '${_accuracyMax != null ? ' / máx: ${_accuracyMax!.toStringAsFixed(0)} m' : ''}',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_distanceToCenter != null &&
                                      _inside == false)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Distancia aprox. al perímetro: '
                                        '${_distanceToCenter!.toStringAsFixed(1)} m',
                                        style: textTheme.bodySmall,
                                      ),
                                    ),
                                  if (_inside == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Te encuentras dentro del perímetro.',
                                        style: textTheme.bodySmall,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _locateAndCheck,
                                      icon: const Icon(Icons.my_location),
                                      label: const Text('Actualizar ubicación'),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ===== BOTÓN PRINCIPAL =====
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _handleMark,
                              icon:
                                  _loading
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.fingerprint),
                              label: Text(
                                _loading
                                    ? 'Enviando...'
                                    : 'Marcar ${_friendlyNextType(nextType)}',
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Asegúrate de tener el GPS activado y estar dentro del perímetro antes de marcar.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // -------- CAPA DE BLOQUEO --------
          if (_appBloqueada)
            AbsorbPointer(
              absorbing: true,
              child: Container(
                alignment: Alignment.center,
                color: Colors.black54,
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Aplicación bloqueada',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(_mensajeBloqueo, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _mostrarDialogoBloqueo,
                          child: const Text(
                            'Más información',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
