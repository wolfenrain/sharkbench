import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'serve.dart';

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serveWithIsolates(
    handler, ip, port, //
    numberOfIsolates: 8,
    onClose: (instance) {},
  );
}
