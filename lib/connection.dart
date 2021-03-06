part of dglux.dgapi;

abstract class IOldApiConnection {
  Future<bool> login();
  Future loginWithError();

  Future<String> loadString(Uri uri, [String post]);
  Future<List<int>> loadBytes(Uri uri, [String post, String contentType, bool isAuthRelated = false]);

  DGDataService get service;
}

HttpClient loader = () {
  var client = new HttpClient();
  client.badCertificateCallback = (a, b, c) => true;
  client.maxConnectionsPerHost = 1024;
  return client;
}();

Future timeoutRequest(HttpClientRequest req) async {
  var f0 = req.close().timeout(new Duration(seconds: 60));
  var f1 = new Future.delayed(new Duration(seconds: 70));
  var resp =  await Future.any([f1,f0]);
  if (resp is HttpClientResponse) {
    return resp;
  }
 throw new Exception('http request timeout');
}
class OldApiBaseAuthConnection implements IOldApiConnection {

  final String serverUrl;
  final String username;
  final String password;
  Uri serverUri;
  String authString;
  DGDataService service;
  bool forceUseSync = false;
  bool basicAuth = true;

  OldApiBaseAuthConnection(this.serverUrl, this.username, this.password) {
    serverUri = Uri.parse(serverUrl);
    authString = BASE64.encode(UTF8.encode("$username:$password"));
  }

  Future<String> loadString(Uri uri, [String post, String contentType, bool isAuthRelated = false, int retries = 0]) async {
    try {
      HttpClientRequest req;

      if (post != null) {
        req = await loader.postUrl(uri);
      } else {
        req = await loader.getUrl(uri);
      }

      authRequest(req);

      if (contentType != null) {
        req.headers.contentType = ContentType.parse(contentType);
      } else if (post != null) {
        req.headers.contentType = ContentType.parse('text/plain;charset=UTF-8');
      }

      if (post != null) {
        req.add(UTF8.encode(post));
      }

      HttpClientResponse resp = await timeoutRequest(req);

      if ((resp.statusCode == HttpStatus.UNAUTHORIZED || resp.statusCode == HttpStatus.NOT_ACCEPTABLE) && !isAuthRelated) {
        await login();
        return await loadString(uri, post, contentType, isAuthRelated, retries + 1);
      }

      if (resp.cookies != null && resp.cookies.isNotEmpty)
        serverCookies = resp.cookies;

      var data = await resp.transform(decoder).join();
      return data;
    } catch (e, stack) {
      if (logger.level <= Level.FINEST) {
        logger.warning("Failed to fetch ${uri.toString()}.", e, stack);
      } else {
        logger.warning("Failed to fetch ${uri.toString()}.", e);
      }

      if (retries > 2) {
        rethrow;
      } else {
        await new Future.delayed(const Duration(seconds: 1));
        return await loadString(
          uri,
          post,
          contentType,
          isAuthRelated,
          retries + 1
        );
      }
    }
  }

  Future<List<int>> loadBytes(Uri uri, [String post, String contentType, bool isAuthRelated = false]) async {
    HttpClientRequest req;

    if (post != null) {
      req = await loader.postUrl(uri);
    } else {
      req = await loader.getUrl(uri);
    }

    authRequest(req);

    if (contentType != null) {
      req.headers.contentType = ContentType.parse(contentType);
    }

    if (post != null) {
      req.add(UTF8.encode(post));
    }

    HttpClientResponse resp = await req.close();

    if ((resp.statusCode == HttpStatus.UNAUTHORIZED || resp.statusCode == HttpStatus.NOT_ACCEPTABLE) && !isAuthRelated) {
      await login();
      return await loadBytes(uri, post, contentType);
    }

    serverCookies = resp.cookies;

    return resp.fold([], (a, b) {
      return a..addAll(b);
    });
  }

  Utf8Decoder decoder = const Utf8Decoder(allowMalformed: true);

  void authRequest(HttpClientRequest req) {
    if (basicAuth) {
      req.headers.add("Authorization", "Basic ${authString}");
    }

    if (serverCookies != null) {
      req.cookies.addAll(serverCookies);
    }
    req.headers.add("Accept-Charset", "utf-8");
    req.headers.add("Accept-Encoding", "gzip, deflate");
  }

  var serverCookies = new List<Cookie>();

  Future loginWithError() async {
    var result = await login();
    if (!result) {
      throw new Exception("Failed!");
    }
  }

  Future<bool> login() async {
    Uri configUri = serverUri.resolve("dgconfig.json");
    String configStr = "";

    try {
      configStr = await loadString(configUri, null, null, true);
    } catch (e) {}

    if (configStr.contains("<html>") || configStr.contains("<!DOCTYPE html>")) {
      String rootStr = await loadString(serverUri);

      if (rootStr.contains("j_security_check") || rootStr.contains("Eclypse")) {
        basicAuth = false;
        var result = await loadString(
            serverUri.resolve("j_security_check"),
            "j_username=${username}&j_password=${password}",
            "application/x-www-form-urlencoded",
            true
        );

        if (result.trim().isNotEmpty) {
          return false;
        }

        configUri = serverUri.resolve("eclypse/envysion/dgconfig.json");
        configStr = await loadString(configUri, null, null, true);
        niagara = false;
      }
    }

    Map config;
    try {
      config = const JsonDecoder().convert(configStr);
    } catch (e) {
      config = {
        "indexUrl": "index.html",
        "viewerUrl": "view.html",
        "dataUrl": "../dgjson",
        "userUrl": "../dguser",
        "assetUrl": "../dgfs",
        "sessionUrl": "../dguser/session",
        "dbUrl": "../dgdb",
        "loginUrl": "../login",
        "logoutUrl": "../logout",
        "updateUrl": "update.html"
      };
    }
    String sessionStr = await loadString(configUri.resolve(config["sessionUrl"]));

    if (sessionStr.contains("DGBox version")) { // This is DGBox
      basicAuth = false;
      var result = await loadString(
          serverUri.resolve("/dglux5-login.htm"),
          "username=${username}&password=${password}",
          "application/x-www-form-urlencoded",
          true
      );

      if (result.trim().isNotEmpty) {
        return false;
      }

      sessionStr = await loadString(
        configUri.resolve("..").resolve(config["sessionUrl"]),
        null,
        null,
        true
      );
      niagara = false;
    }

    Map session = const JsonDecoder().convert(sessionStr);

    if (!setup) {
      setup = true;

      var cn = session["connection"];
      void useAsyncConn() {
        service = new DGDataServiceAsync(
          serverUrl,
          configUri.resolve(config["dataUrl"]).toString(),
          configUri.resolve(config["dbUrl"]).toString(),
          this
        );
      }

      void useSyncConn() {
        service = new DGDataService(
          serverUrl,
          configUri.resolve(config["dataUrl"]).toString(),
          configUri.resolve(config["dbUrl"]).toString(),
          this
        );
      }

      if (cn != null) {
        var conns = cn.split(",");

        if (conns.contains("async")) {
          useAsyncConn();
        } else {
          useSyncConn();
        }
      } else {
        useSyncConn();
      }

      service.niagara = niagara;
    }

    return true;
  }

  bool setup = false;
  bool niagara = true;
}
