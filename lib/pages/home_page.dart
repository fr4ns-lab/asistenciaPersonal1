import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---- Estado
  Position? _position;
  bool? _inside; // null = aún no calculado
  double? _accuracyMax; // metros
  List<LatLng> _polygon = []; // puntos del polígono
  GoogleMapController? _mapCtrl;
  StreamSubscription<Position>? _posSub;

  LatLng? _parseLatLngString(String s) {
    // Ejemplo de s: "[16.401140695422633° S, 71.52505081404384° W]"
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
    if (latH == 'N') lat = lat;
    if (lngH == 'W') lng = -lng;
    if (lngH == 'E') lng = lng;

    return LatLng(lat, lng);
  }

  // ---- Carga geocerca desde Firestore
  Future<void> _loadGeofence() async {
    try {
      final doc =
          await FirebaseFirestore.instance.doc('settings/geofence').get();
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
        // 1) GeoPoint directamente en el array
        if (p is GeoPoint) {
          pts.add(LatLng(p.latitude, p.longitude));
          continue;
        }
        // 2) Map con {lat, lng} o {geopoint: GeoPoint}
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
        // 3) (Opcional) String como "[16.40° S, 71.52° W]" por si hubiera alguno
        if (p is String) {
          final parsed = _parseLatLngString(p); // deja esta helper si la tenías
          if (parsed != null) {
            pts.add(parsed);
            continue;
          }
        }
        debugPrint('Tipo no soportado en points: ${p.runtimeType} -> $p');
      }

      _accuracyMax = (data['accuracyMax'] as num?)?.toDouble();
      _polygon = pts;

      debugPrint('Polígono cargado: ${_polygon.length} puntos');
      for (final q in _polygon) {
        debugPrint('  • ${q.latitude}, ${q.longitude}');
      }

      if (mounted) {
        setState(() {});
        // centra el mapa al polígono si ya está creado
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
          await _mapCtrl!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 80),
          );
        }
      }
    } catch (e) {
      debugPrint('Error al cargar geofence: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error Firestore: $e')));
      }
    }
  }

  // ---- Permisos y servicios
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
            content: Text('Permiso denegado permanentemente. Ve a Ajustes.'),
          ),
        );
      }
      return false;
    }
    return true;
  }

  // ---- Punto en polígono (ray casting). Usa LatLng de google_maps_flutter.
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

    // Rechaza lecturas con baja precisión si tienes accuracyMax
    if (_accuracyMax != null && pos.accuracy > _accuracyMax!) {
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (_) {
        // nos quedamos con la lectura anterior
      }
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

    // Centra la cámara si ya existe el mapa
    if (_mapCtrl != null) {
      await _mapCtrl!.animateCamera(
        CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
      );
    }

    if (mounted) {
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
  }

  void _listenPosition() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // cada 5 m
      ),
    ).listen((pos) {
      final nowInside =
          _polygon.isNotEmpty
              ? _pointInPolygon(LatLng(pos.latitude, pos.longitude), _polygon)
              : false;

      final changed = (_inside != null && _inside != nowInside);
      _position = pos;
      _inside = nowInside;

      if (mounted) {
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
        // mueve cámara suavemente
        _mapCtrl?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    () async {
      await _loadGeofence();
      await _locateAndCheck();
      _listenPosition();
    }();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  LatLng _polygonCenter() {
    if (_polygon.isEmpty)
      return const LatLng(-16.3989, -71.5369); // fallback: Arequipa centro
    double sumLat = 0, sumLng = 0;
    for (final p in _polygon) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / _polygon.length, sumLng / _polygon.length);
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;

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

    return Scaffold(
      appBar: AppBar(title: const Text('Geocerca La Salle')),
      body: Column(
        children: [
          // --- Mapa ---
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target:
                    _polygon.isNotEmpty
                        ? _polygonCenter()
                        : (pos != null
                            ? LatLng(pos.latitude, pos.longitude)
                            : const LatLng(-16.3989, -71.5369)),
                zoom: _polygon.isNotEmpty ? 17 : 20,
              ),
              polygons: polygons,
              markers: markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (c) => _mapCtrl = c,
              compassEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),

          // --- Info / Controles ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    Chip(
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
                        label: Text(
                          'Precisión: ${pos.accuracy.toStringAsFixed(1)} m'
                          '${_accuracyMax != null ? ' / máx: ${_accuracyMax!.toStringAsFixed(0)} m' : ''}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  pos == null
                      ? 'Ubicación: (sin datos aún)'
                      : 'Lat: ${pos.latitude.toStringAsFixed(6)} | Lng: ${pos.longitude.toStringAsFixed(6)}',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _locateAndCheck,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Actualizar ubicación'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
