part of dglux.dgapi;

abstract class IOldApiConnection {
  Future<bool> login();
  Future loginWithError();

  Future<String> loadString(Uri uri, [String post]);
  Future<List<int>> loadBytes(Uri uri, [String post, String contentType, bool isAuthRelated = false]);

  DGDataService get service;
}

HttpClient loader = new HttpClient()
  ..badCertificateCallback = (a, b, c) => true;

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
    authString = CryptoUtils.bytesToBase64(UTF8.encode('$username:$password'));
  }

  Future<String> loadString(Uri uri, [String post, String contentType, bool isAuthRelated = false]) async {
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

    if (resp.statusCode == HttpStatus.UNAUTHORIZED && !isAuthRelated) {
      await login();
      return await loadString(uri, post, contentType);
    }

    addCookie(resp.headers.value('set-cookie'));
    var data = await resp.transform(decoder).join();
    return data;
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

    if (resp.statusCode == HttpStatus.UNAUTHORIZED && !isAuthRelated) {
      await login();
      return await loadBytes(uri, post, contentType);
    }

    addCookie(resp.headers.value('set-cookie'));
    return resp.fold([], (a, b) {
      return a..addAll(b);
    });
  }

  Utf8Decoder decoder = const Utf8Decoder(allowMalformed: true);

  void authRequest(HttpClientRequest req) {
    if (basicAuth) {
      req.headers.add('Authorization', 'Basic ${authString}');
    }

    if (serverCookie != null) {
      req.headers.add('cookie', serverCookie);
    }
    req.headers.add('Accept-Charset', 'utf-8');
    req.headers.add('Accept-Encoding', 'gzip, deflate');
  }

  String serverCookie;

  void addCookie(String cookie) {
    if (cookie != null) {
      serverCookie = cookie.split(';').where((str) => !str.toLowerCase().contains('path=')).join(';');
    }
  }

  Future loginWithError() async {
    var result = await login();
    if (!result) {
      throw new Exception("Failed!");
    }
  }

  Future<bool> login() async {
    Uri configUri = serverUri.resolve('dgconfig.json');
    String configStr = "";

    try {
      configStr = await loadString(configUri, null, null, true);
    } catch (e) {}

    if (configStr.contains("<html>")) {
      String rootStr = await loadString(serverUri);

      if (rootStr.contains("j_security_check")) {
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

        configUri = serverUri.resolve('eclypse/envysion/dgconfig.json');
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
    String sessionStr = await loadString(configUri.resolve(config['sessionUrl']));

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

      sessionStr = await loadString(configUri.resolve("..").resolve(config['sessionUrl']), null, null, true);
      niagara = false;
    }

    Map session = const JsonDecoder().convert(sessionStr);

    if (!setup) {
      setup = true;

      var cn = session['connection'];

      void useAsyncConn() {
        service = new DGDataServiceAsync(
          serverUrl,
          configUri.resolve(config['dataUrl']).toString(),
          configUri.resolve(config['dbUrl']).toString(),
          this
        );
      }

      void useSyncConn() {
        service = new DGDataService(
          serverUrl,
          configUri.resolve(config['dataUrl']).toString(),
          configUri.resolve(config['dbUrl']).toString(),
          this
        );
      }

      if (cn != null) {
        var conns = cn.split(",");

        if (conns.contains("async") && !forceUseSync) {
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
