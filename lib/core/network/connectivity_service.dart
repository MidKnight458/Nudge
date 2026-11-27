import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstraction over network reachability checks and change events.
abstract interface class ConnectivityService {
  Future<bool> get isOnline;

  Stream<bool> get onConnectivityChanged;
}

/// Default [ConnectivityService] backed by `connectivity_plus`.
class ConnectivityServiceImpl implements ConnectivityService {
  ConnectivityServiceImpl({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  @override
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(_hasConnection).distinct();
  }

  static bool _hasConnection(List<ConnectivityResult> results) {
    return results.any(
      (ConnectivityResult result) => result != ConnectivityResult.none,
    );
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((Ref ref) {
  return ConnectivityServiceImpl();
});

final isOnlineProvider = StreamProvider<bool>((Ref ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.isOnline;
  yield* service.onConnectivityChanged;
});
