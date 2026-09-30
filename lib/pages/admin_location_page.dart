import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Herramienta para administradores: muestra la ubicación actual respecto de
/// la geocerca publicada y permite guardar una colección de puntos como
/// borrador para una futura edición.
class AdminLocationPage extends StatefulWidget {
  const AdminLocationPage({super.key});

  @override
  State<AdminLocationPage> createState() => _AdminLocationPageState();
}

class _AdminLocationPageState extends State<AdminLocationPage> {
  final _db = FirebaseFirestore.instance;
  Position? _position;
  List<LatLng> _polygon = const [];
  final List<LatLng> _capturedPoints = [];
  StreamSubscription<Position>? _positionSubscription;
  GoogleMapController? _mapController;
  bool _loading = true;
  bool _collecting = false;
  bool? _inside;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _loadGeofence().timeout(const Duration(seconds: 10));
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo cargar el perímetro: $error');
    }

    // La vista y el mapa no deben depender de que el GPS entregue una
    // lectura inmediata. El seguimiento continúa en segundo plano.
    if (mounted) setState(() => _loading = false);

    try {
      await _startLocation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadGeofence() async {
    final snapshot = await _db.doc('settings/geofence').get();
    final raw = snapshot.data()?['points'];
    if (raw is! List) return;

    final points = <LatLng>[];
    for (final value in raw) {
      if (value is GeoPoint) {
        points.add(LatLng(value.latitude, value.longitude));
      } else if (value is Map && value['lat'] is num && value['lng'] is num) {
        points.add(
          LatLng((value['lat'] as num).toDouble(), (value['lng'] as num).toDouble()),
        );
      } else if (value is Map && value['geopoint'] is GeoPoint) {
        final point = value['geopoint'] as GeoPoint;
        points.add(LatLng(point.latitude, point.longitude));
      } else if (value is String) {
        final parsed = _parseLatLng(value);
        if (parsed != null) points.add(parsed);
      }
    }
    if (mounted) setState(() => _polygon = points);
  }

  LatLng? _parseLatLng(String value) {
    final match = RegExp(
      r'([\d.]+)\D*([NSEW])\s*,\s*([\d.]+)\D*([NSEW])',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    var latitude = double.parse(match.group(1)!);
    var longitude = double.parse(match.group(3)!);
    if (match.group(2)!.toUpperCase() == 'S') latitude = -latitude;
    if (match.group(4)!.toUpperCase() == 'W') longitude = -longitude;
    return LatLng(latitude, longitude);
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Activa los servicios de ubicación para continuar.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('El permiso de ubicación no está disponible.');
    }

    final known = await Geolocator.getLastKnownPosition();
    if (known != null) _updatePosition(known);

    try {
      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 8),
      );
      _updatePosition(current);
    } on TimeoutException {
      if (known == null) {
        throw Exception('No se obtuvo una lectura GPS. Verifica la señal y vuelve a intentar.');
      }
    }
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen(_updatePosition);
  }

  void _updatePosition(Position position) {
    final inside = _polygon.length >= 3
        ? _pointInPolygon(
            LatLng(position.latitude, position.longitude),
            _polygon,
          )
        : null;
    if (!mounted) return;
    setState(() {
      _position = position;
      _inside = inside;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
    );
  }

  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) /
                      ((yj - yi) == 0 ? 1e-12 : yj - yi) +
                  xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  void _captureCurrentPoint() {
    final position = _position;
    if (position == null) return;
    setState(() {
      _capturedPoints.add(LatLng(position.latitude, position.longitude));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Punto ${_capturedPoints.length} capturado.')),
    );
  }

  Future<void> _saveCapturedPoints() async {
    if (_capturedPoints.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    await _db.collection('settings').doc('geofence_captures').collection('drafts').doc(uid).set({
      'points': _capturedPoints
          .map((point) => GeoPoint(point.latitude, point.longitude))
          .toList(),
      'capturedAt': FieldValue.serverTimestamp(),
      'capturedBy': uid,
      'source': 'admin_location_tool',
    }, SetOptions(merge: true));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Borrador guardado en Firestore.')),
    );
  }

  LatLng get _initialTarget => _position == null
      ? (_polygon.isNotEmpty ? _polygon.first : const LatLng(-12.0464, -77.0428))
      : LatLng(_position!.latitude, _position!.longitude);

  @override
  Widget build(BuildContext context) {
    final color = _inside == true
        ? const Color(0xFF16A34A)
        : _inside == false
            ? const Color(0xFFDC2626)
            : const Color(0xFFCA8A04);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        title: const Text('Ubicación y perímetro'),
        backgroundColor: const Color(0xFFF4F8FF),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
              children: [
                if (_error != null) _MessageCard(message: _error!),
                Container(
                  height: 330,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: _initialTarget, zoom: 17),
                    onMapCreated: (controller) => _mapController = controller,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    polygons: _polygon.isEmpty
                        ? {}
                        : {
                            Polygon(
                              polygonId: const PolygonId('official_geofence'),
                              points: _polygon,
                              strokeWidth: 3,
                              strokeColor: color,
                              fillColor: color.withValues(alpha: 0.18),
                            ),
                          },
                    markers: {
                      if (_position != null)
                        Marker(
                          markerId: const MarkerId('admin_location'),
                          position: LatLng(_position!.latitude, _position!.longitude),
                          infoWindow: const InfoWindow(title: 'Mi ubicación'),
                        ),
                      ..._capturedPoints.asMap().entries.map(
                        (entry) => Marker(
                          markerId: MarkerId('capture_${entry.key}'),
                          position: entry.value,
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                          infoWindow: InfoWindow(title: 'Punto ${entry.key + 1}'),
                        ),
                      ),
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  elevation: 0,
                  color: color.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(_inside == true ? Icons.check_circle : Icons.location_on, color: color, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _inside == true ? 'Dentro del perímetro' : _inside == false ? 'Fuera del perímetro' : 'Verificando ubicación',
                                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 17),
                              ),
                              Text(
                                _position == null ? 'Sin lectura GPS' : 'Precisión aproximada: ${_position!.accuracy.toStringAsFixed(1)} m',
                                style: const TextStyle(color: Color(0xFF475569)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Recopilar puntos para editar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        const Text('Captura puntos GPS y guárdalos como borrador. No cambia la geocerca oficial.'),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Modo recopilación'),
                          subtitle: Text('${_capturedPoints.length} punto(s) capturado(s)'),
                          value: _collecting,
                          onChanged: (value) => setState(() => _collecting = value),
                        ),
                        FilledButton.icon(
                          onPressed: _collecting ? _captureCurrentPoint : null,
                          icon: const Icon(Icons.add_location_alt_rounded),
                          label: const Text('Capturar ubicación actual'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _capturedPoints.isEmpty ? null : _saveCapturedPoints,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Guardar borrador en Firestore'),
                        ),
                        if (_capturedPoints.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _capturedPoints.clear()),
                            child: const Text('Limpiar puntos'),
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFEF2F2),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(message, style: const TextStyle(color: Color(0xFF991B1B))),
        ),
      );
}
