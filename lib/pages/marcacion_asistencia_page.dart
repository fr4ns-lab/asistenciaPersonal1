import 'dart:async';

import 'package:asistenciapersonal1/models/transaction_request.dart';
import 'package:asistenciapersonal1/pages/login_page.dart';
import 'package:asistenciapersonal1/services/transaction_api.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ntp/ntp.dart';

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

  Future<void> _syncTimeFromNTP() async {
    try {
      // Hora “real” desde un servidor NTP (por defecto pool.ntp.org)
      final ntpNow = await NTP.now();

      final deviceNow = DateTime.now();
      // ntpNow = deviceNow + offset  => offset = ntpNow - deviceNow
      final offset = ntpNow.difference(deviceNow);

      if (!mounted) return;
      setState(() {
        _serverOffset = offset;
        _now = ntpNow; // inicializamos el reloj con la hora NTP
      });
    } catch (e) {
      debugPrint('Error NTP: $e');
      // Si falla NTP, simplemente sigues con la hora del dispositivo como fallback
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

  @override
  void initState() {
    super.initState();
    _api = TransactionApi(baseUrl: 'https://apiasistencia.lasalle.edu.pe');

    _startClock();
    _initUserData();

    // Cargar geocerca; el ajuste de cámara y ubicación se hará
    // cuando el mapa esté listo (onMapCreated).
    _loadGeofence();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _posSub?.cancel();

    _mapCtrl?.dispose();
    _mapCtrl = null; // 👈 importante para evitar usar un controller muerto

    super.dispose();
  }

  // ----------------- RELOJ -----------------
  void _startClock() {
    // Primero intentamos sincronizar con NTP una vez
    _syncTimeFromNTP();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      final deviceNow = DateTime.now();
      DateTime displayNow;

      if (_serverOffset != null) {
        // Hora mostrada = hora del dispositivo + desfase medido
        displayNow = deviceNow.add(_serverOffset!);
      } else {
        // Si aún no tenemos offset (porque NTP falló o no respondió),
        // usamos la hora local como fallback
        displayNow = deviceNow;
      }

      setState(() {
        _now = displayNow;
      });
    });
  }

  // ----------------- DATOS DE USUARIO -----------------
  Future<void> _initUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final doc = await _db.collection('users').doc(uid).get();

    if (!mounted) return;
    setState(() {
      _email = user.email;
      _nombre = user.displayName ?? doc.data()?['name'];
      _dni = doc.data()?['dni'];
    });
  }

  // ----------------- GEOFERNCE DESDE FIRESTORE -----------------

  LatLng? _parseLatLngString(String s) {
    // Ejemplo de s: "[16.40114° S, 71.52505° W]"
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

  // ----------------- PERMISOS / POSICIÓN -----------------
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

  LatLng _polygonCenter() {
    if (_polygon.isEmpty) {
      return const LatLng(-16.3989, -71.5369); // fallback: Arequipa centro
    }
    double sumLat = 0, sumLng = 0;
    for (final p in _polygon) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / _polygon.length, sumLng / _polygon.length);
  }

  Future<void> _locateAndCheck() async {
    final ok = await _ensurePermissions();
    if (!ok) return;

    var pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );

    // Reintento si la precisión no es buena
    if (_accuracyMax != null && pos.accuracy > _accuracyMax!) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
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

    final center = _polygonCenter();
    _distanceToCenter = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      center.latitude,
      center.longitude,
    );

    // Mover cámara si el mapa sigue vivo
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

      final center = _polygonCenter();
      _distanceToCenter = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        center.latitude,
        center.longitude,
      );

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

  // ----------------- API BIOTIME (USA TransactionApi) -----------------

  Future<void> _enviarMarcacionBiotime({
    required String empCode,
    required double lat,
    required double lng,
  }) async {
    // Construimos el body para TransactionIn / TransactionRequest
    // punch_time = null => lo pone el servidor (NOW())
    final tx = TransactionRequest(
      empCode: empCode,
      punchTime: null,
      longitude: lng,
      latitude: lat,
      // Puedes guardar una referencia básica en gpsLocation
      gpsLocation: 'Lat: $lat, Lng: $lng',
      mobile: null,
    );

    await _api.sendTransaction(tx);
  }

  // ----------------- LÓGICA DE MARCACIÓN -----------------
  String _nextMarkType() {
    // Por ahora es solo en memoria: si la última fue entrada, ahora salida.
    if (_lastMarkType == 'entrada') return 'salida';
    return 'entrada';
  }

  Future<void> _handleMark() async {
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
        // Si quieres redirigir automáticamente:
        // Navigator.of(context).pushReplacement(
        //   MaterialPageRoute(builder: (_) => const LoginPage()),
        // );
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
      // Actualizar ubicación y estado de geocerca antes de marcar
      await _locateAndCheck();

      final pos = _position;
      final isInside = _inside ?? false;

      if (pos == null || !isInside) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Estás fuera del área permitida.\n'
                'Distancia aprox.: ${_distanceToCenter?.toStringAsFixed(1) ?? '-'} m',
              ),
            ),
          );
        }
        return;
      }

      final tipo = _nextMarkType();

      // 👉 Mandar a tu API de Biotime (ahora con TransactionApi)
      await _enviarMarcacionBiotime(
        empCode: _dni!, // asumimos que emp_code = DNI
        lat: pos.latitude,
        lng: pos.longitude,
      );

      if (!mounted) return;

      setState(() {
        _lastMarkType = tipo;
        _lastMarkTime = DateTime.now();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marcación de $tipo registrada correctamente.')),
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

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pos = _position;
    final nextType = _nextMarkType();

    final polygons =
        _polygon.isEmpty
            ? <Polygon>{}
            : {
              Polygon(
                polygonId: const PolygonId('geofence'),
                points: _polygon,
                fillColor: Colors.green.withOpacity(0.2),
                strokeColor: Colors.green,
                strokeWidth: 2,
              ),
            };

    final markers = <Marker>{
      if (pos != null)
        Marker(
          markerId: const MarkerId('me'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: InfoWindow(
            title: 'Tu ubicación',
            snippet: 'Precisión: ${pos.accuracy.toStringAsFixed(1)} m',
          ),
        ),
    };

    final size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de asistencia'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ---- MAPA: altura fija (40–45% pantalla) ----
          SizedBox(
            height: size.height * 0.42,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target:
                      _polygon.isNotEmpty
                          ? _polygonCenter()
                          : (pos != null
                              ? LatLng(pos.latitude, pos.longitude)
                              : const LatLng(-16.3989, -71.5369)),
                  zoom: _polygon.isNotEmpty ? 17 : 18,
                ),
                polygons: polygons,
                markers: markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                compassEnabled: true,
                mapToolbarEnabled: false,
                onMapCreated: (c) async {
                  _mapCtrl = c;
                  // Una vez que el mapa está listo, ubicamos y empezamos a escuchar
                  await _locateAndCheck();
                  _listenPosition();
                },
              ),
            ),
          ),

          // ---- INFO + BOTÓN: scrollable ----
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
                    // Card usuario + hora
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
                              radius: 24,
                              child: Text(
                                (_nombre ?? 'U').isNotEmpty
                                    ? (_nombre ?? 'U')[0].toUpperCase()
                                    : 'U',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_nombre != null)
                                    Text(
                                      _nombre!,
                                      style: textTheme.titleMedium,
                                    ),
                                  if (_email != null)
                                    Text(_email!, style: textTheme.bodySmall),
                                  if (_dni != null)
                                    Text(
                                      'DNI: $_dni',
                                      style: textTheme.bodySmall,
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 18),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Hora actual: '
                                        '${_now.hour.toString().padLeft(2, '0')}:'
                                        '${_now.minute.toString().padLeft(2, '0')}:'
                                        '${_now.second.toString().padLeft(2, '0')}',
                                        style: textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (_lastMarkTime != null)
                                    Text(
                                      'Última marcación (sesión): '
                                      '$_lastMarkType a las '
                                      '${_lastMarkTime!.hour.toString().padLeft(2, '0')}:'
                                      '${_lastMarkTime!.minute.toString().padLeft(2, '0')}',
                                      style: textTheme.bodySmall,
                                    )
                                  else
                                    Text(
                                      'Sin marcaciones en esta sesión.',
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

                    // Card estado de geocerca
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
                            Text(
                              'Estado de ubicación',
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar: Icon(
                                    _inside == null
                                        ? Icons.help_outline
                                        : (_inside!
                                            ? Icons.check_circle
                                            : Icons.warning_amber_rounded),
                                    size: 18,
                                  ),
                                  label: Text(
                                    _inside == null
                                        ? 'Sin estado'
                                        : (_inside!
                                            ? 'Dentro del perímetro'
                                            : 'Fuera del perímetro'),
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
                                      'Precisión: ${pos.accuracy.toStringAsFixed(1)} m'
                                      '${_accuracyMax != null ? ' / máx: ${_accuracyMax!.toStringAsFixed(0)} m' : ''}',
                                    ),
                                  ),
                              ],
                            ),
                            if (_distanceToCenter != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Distancia aprox. al colegio: '
                                  '${_distanceToCenter!.toStringAsFixed(1)} m',
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botón principal
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
                              : 'Marcar $nextType'.toUpperCase(),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
