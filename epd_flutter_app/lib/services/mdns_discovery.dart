import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

/// A device discovered via mDNS.
class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final List<String> addresses;

  const DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
  });
}

/// Scans the local network for EPD display devices via mDNS.
class MdnsDiscovery {
  MDnsClient? _client;

  /// Start scanning for EPD devices. Yields [DiscoveredDevice] as found.
  Stream<DiscoveredDevice> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    _client = MDnsClient();
    await _client!.start();

    final controller = StreamController<DiscoveredDevice>();

    _client!
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_http._tcp.local'),
        )
        .toList()
        .then((ptrRecords) async {
          for (final ptr in ptrRecords) {
            if (!ptr.domainName.toLowerCase().contains('epd')) continue;

            try {
              final srvRecords = await _client!
                  .lookup<SrvResourceRecord>(
                    ResourceRecordQuery.service(ptr.domainName),
                  )
                  .toList();

              for (final srv in srvRecords) {
                final ipRecords = await _client!
                    .lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv4(srv.target),
                    )
                    .toList();

                final addresses = ipRecords
                    .map((r) => r.address.address)
                    .toList();

                if (addresses.isNotEmpty) {
                  controller.add(DiscoveredDevice(
                    name: ptr.domainName,
                    host: addresses.first,
                    port: srv.port,
                    addresses: addresses,
                  ));
                }
              }
            } catch (_) {
              // Skip devices that fail to resolve
            }
          }
          controller.close();
        })
        .catchError((_) {
          controller.close();
        });

    Timer(timeout, () {
      _client?.stop();
      if (!controller.isClosed) controller.close();
    });

    yield* controller.stream;
  }

  void stop() {
    _client?.stop();
    _client = null;
  }
}
