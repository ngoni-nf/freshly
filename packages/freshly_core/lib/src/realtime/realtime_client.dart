import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/models.dart';

/// Realtime channel for live tracking, dispatch offers and safety events.
///
/// Reconnection matters more here than in most apps: a provider driving
/// through Johannesburg will drop off the network repeatedly, and the client
/// staring at the tracking map must not be told the job has failed because a
/// socket blinked. The socket reconnects with backoff and the UI falls back to
/// polling the booking endpoint whenever the channel is down.
class RealtimeClient {
  RealtimeClient({required this.baseUrl});

  final String baseUrl;
  io.Socket? _socket;

  final _status = StreamController<RealtimeConnectionState>.broadcast();
  final _tracking = StreamController<TrackingUpdate>.broadcast();
  final _offers = StreamController<DispatchOffer>.broadcast();
  final _offerRevoked = StreamController<String>.broadcast();
  final _addonRequests = StreamController<Map<String, dynamic>>.broadcast();
  final _messages = StreamController<ChatMessage>.broadcast();

  Stream<RealtimeConnectionState> get status => _status.stream;
  Stream<TrackingUpdate> get tracking => _tracking.stream;
  Stream<DispatchOffer> get offers => _offers.stream;
  Stream<String> get offerRevoked => _offerRevoked.stream;
  Stream<Map<String, dynamic>> get addonRequests => _addonRequests.stream;
  Stream<ChatMessage> get messages => _messages.stream;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String accessToken) {
    disconnect();

    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .disableAutoConnect()
          .build(),
    );

    socket
      ..onConnect((_) => _status.add(RealtimeConnectionState.connected))
      ..onDisconnect((_) => _status.add(RealtimeConnectionState.disconnected))
      ..onConnectError((_) => _status.add(RealtimeConnectionState.reconnecting))
      ..on('booking.status', (d) => _emitTracking(d))
      ..on('location.ping', (d) => _emitTracking(d))
      ..on('dispatch.offer', (d) {
        if (d is Map)
          _offers.add(DispatchOffer.fromJson(Map<String, dynamic>.from(d)));
      })
      ..on('dispatch.revoked', (d) {
        if (d is Map) _offerRevoked.add(d['offerId'] as String);
      })
      ..on('addon.requested', (d) {
        if (d is Map) _addonRequests.add(Map<String, dynamic>.from(d));
      })
      ..on('chat.message', (d) {
        if (d is Map) {
          _messages.add(ChatMessage.fromJson(Map<String, dynamic>.from(d)));
        }
      });

    _status.add(RealtimeConnectionState.connecting);
    socket.connect();
    _socket = socket;
  }

  void _emitTracking(dynamic payload) {
    if (payload is Map) {
      _tracking
          .add(TrackingUpdate.fromJson(Map<String, dynamic>.from(payload)));
    }
  }

  void joinBooking(String bookingId) =>
      _socket?.emit('booking.subscribe', {'bookingId': bookingId});
  void leaveBooking(String bookingId) =>
      _socket?.emit('booking.unsubscribe', {'bookingId': bookingId});

  /// Providers stream position while a job is live. Five seconds is the
  /// cadence the backend expects; the payload is held in Redis under a TTL and
  /// never written to durable storage.
  void publishLocation(double lat, double lng,
      {double? heading, double? speedKph}) {
    _socket?.emit('location.publish', {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speedKph != null) 'speedKph': speedKph,
    });
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _status.close();
    _tracking.close();
    _offers.close();
    _offerRevoked.close();
    _addonRequests.close();
    _messages.close();
  }
}

enum RealtimeConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected;

  bool get isDegraded => this != RealtimeConnectionState.connected;
}
