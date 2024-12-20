import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dart_frog/dart_frog.dart';

/// Serve a Dart Frog HTTP server using isolates.
///
/// By default it will serve on a single isolate (the main one) which is also
/// the default implementation of [serve].
///
/// If [numberOfIsolates] is specified it will spawn that many isolates that all
/// will run a HTTP server on [address]:[port]. These servers are shared and can
/// handle the request load together.
///
/// If required the instance number the [handler] is being executed on can be
/// found on [RequestContext] as `instance`.
Future<HttpServer> serveWithIsolates(
  Handler handler,
  Object address,
  int port, {
  String? poweredByHeader = 'Dart with package:dart_frog',
  SecurityContext? securityContext,
  FutureOr<void> Function(int instance)? onClose,
  int numberOfIsolates = 1,
}) async {
  assert(numberOfIsolates >= 1, 'Number of isolates should be at least 1');
  // TODO(wolfen): it is recommended to not go higher but do we want to enforce it?
  // assert(
  //   numberOfIsolates <= Platform.numberOfProcessors,
  //   'Number of isolates should not exceed amount of processors available',
  // );

  final isolates = <({Stream<dynamic> incoming, SendPort sendPort})>[];

  // We start at 1 as the main isolate will run it's own HTTP server, this
  // server acts as the boss and will try and close all other servers first
  // before closing itself.
  for (var i = 1; i < numberOfIsolates; i += 1) {
    // Create the receiving port and spawn a new isolate.
    final receivePort = ReceivePort();
    await Isolate.spawn(_serveOnIsolate, receivePort.sendPort);

    // Turn the receiving port into a broadcast stream as we only want to know
    // what comes in, whenever we want.
    final incoming = receivePort.asBroadcastStream();

    // The isolate should always give us a SendPort first.
    final sendPort = await incoming.pop<SendPort>();
    isolates.add((incoming: incoming, sendPort: sendPort));

    // Tell the isolate where it should run it's HTTP server on.
    sendPort.send(
      _ServeArgs(
        handler, address, port, //
        poweredByHeader: poweredByHeader,
        securityContext: securityContext,
        instance: i,
        onClose: onClose,
      ),
    );
  }

  // Create a HTTP server on the main isolate.
  final server = await _ProxyHttpServer.create(
    _ServeArgs(
      handler, address, port, //
      poweredByHeader: poweredByHeader,
      securityContext: securityContext,
      instance: 0,
      onClose: (instance) async {
        // Try to close each server on every spawned isolate, if any error
        // occurs it will be propagated upwards once all the other isolates have
        // tried to close their server instance.
        await Future.wait(
          isolates.map((isolate) async {
            isolate.sendPort.send(true);

            // If an error was received we throw it with the given stack trace.
            final err = await isolate.incoming.pop<Object?>();
            if (err != null) {
              Error.throwWithStackTrace(err, await isolate.incoming.pop());
            }
          }),
        );
        return onClose?.call(instance);
      },
    ),
  );

  // If SIGINT or SIGTERM signals were emitted, close the server and exit out.
  final signals = [ProcessSignal.sigint, ProcessSignal.sigterm];
  Future.any(signals.map((e) => e.watch().first)).then((signal) async {
    await server.close(force: true);
    return exit(0);
  }).ignore();

  return server;
}

Future<Never> _serveOnIsolate(SendPort sendPort) async {
  // Send the SendPort to the parent for communication.
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  // Turn the receiving port into a broadcast stream as we only want to know
  // what comes in, whenever we want.
  final incoming = receivePort.asBroadcastStream();

  // The parent isolate should always give us _ServeArgs first so we can use
  // it to create an isolated HTTP server.
  final server = await _ProxyHttpServer.create(await incoming.pop());

  try {
    // The next value we get is when the main HTTP server gets closed, it is the
    // boolean force value of the close method.
    await server.close(force: await incoming.pop());

    // No error occurred so we can just send null.
    sendPort.send(null);
  } catch (err, stackTrace) {
    // Caught error, emitting it to the parent isolate.
    sendPort
      ..send(err)
      ..send(stackTrace);
  }

  // We can now safely close our receiving port and exit the Isolate.
  receivePort.close();
  return Isolate.exit();
}

/// [HttpServer] implementation that is able to propagate the [close] event.
class _ProxyHttpServer extends StreamView<HttpRequest> implements HttpServer {
  _ProxyHttpServer(
    this._server, {
    required FutureOr<void> Function() onClose,
  })  : _onClose = onClose,
        super(_server);

  static Future<HttpServer> create(_ServeArgs args) async {
    final info = _IsolatedInformation(instance: args.instance);
    return _ProxyHttpServer(
      await serve(
        (c) => args.handler(c.provide(() => info)),
        args.address,
        args.port,
        shared: true,
      ),
      onClose: () => args.onClose?.call(args.instance),
    );
  }

  final HttpServer _server;

  final FutureOr<void> Function() _onClose;

  @override
  bool get autoCompress => _server.autoCompress;
  @override
  set autoCompress(bool autoCompress) => _server.autoCompress = autoCompress;

  @override
  Duration? get idleTimeout => _server.idleTimeout;
  @override
  set idleTimeout(Duration? idleTimeout) => _server.idleTimeout = idleTimeout;

  @override
  String? get serverHeader => _server.serverHeader;
  @override
  set serverHeader(String? serverHeader) => _server.serverHeader = serverHeader;

  @override
  InternetAddress get address => _server.address;

  @override
  int get port => _server.port;

  @override
  HttpHeaders get defaultResponseHeaders => _server.defaultResponseHeaders;

  @override
  set sessionTimeout(int timeout) => _server.sessionTimeout = timeout;

  @override
  Future<void> close({bool force = false}) async {
    await _onClose();
    return _server.close(force: force);
  }

  @override
  HttpConnectionsInfo connectionsInfo() => _server.connectionsInfo();
}

/// Arguments used for starting a [_ProxyHttpServer] with
/// [_ProxyHttpServer.create].
class _ServeArgs {
  const _ServeArgs(
    this.handler,
    this.address,
    this.port, {
    required this.poweredByHeader,
    required this.securityContext,
    required this.instance,
    required this.onClose,
  });

  final Handler handler;

  final Object address;

  final int port;

  final String? poweredByHeader;

  final SecurityContext? securityContext;

  final int instance;

  final FutureOr<void> Function(int instance)? onClose;
}

extension IsolatedContext on RequestContext {
  int get instance => read<_IsolatedInformation>().instance;
}

class _IsolatedInformation {
  const _IsolatedInformation({required this.instance});

  final int instance;
}

extension on Stream<dynamic> {
  Future<T> pop<T>() async => await first as T;
}
