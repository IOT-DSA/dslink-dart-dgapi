part of dglux.dgapi;

abstract class IOldApiConnection {
  Future<bool> login();

  Future<String> loadString(Uri uri, [String post]);

  DGDataService get service;
}

List foldList(List a, List b) {
  return a
    ..addAll(b);
}

class OldApiBaseAuthConnection implements IOldApiConnection {
  final String serverUrl;
  final String username;
  final String password;
  Uri serverUri;
  String authString;
  DGDataService service;
  bool basicAuth = true;

  OldApiBaseAuthConnection(this.serverUrl, this.username, this.password) {
    serverUri = Uri.parse(serverUrl);
    authString = CryptoUtils.bytesToBase64(UTF8.encode('$username:$password'));
  }

  Future<String> loadString(Uri uri, [String post, String contentType]) async {
    HttpClient loader = new HttpClient();
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
    addCookie(resp.headers.value('set-cookie'));
    List respBytes = await resp.fold([], foldList);
    return decoder.convert(respBytes);
  }

  Utf8Decoder decoder = new Utf8Decoder(allowMalformed: true);

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

  Future<bool> login() async{
    String configStr = await loadString(serverUri.resolve('dgconfig.json'));
    Map config = JSON.decode(configStr);
    String sessionStr = await loadString(serverUri.resolve(config['sessionUrl']));
    if (sessionStr.contains("DGBox version")) { // This is DGBox
      basicAuth = false;
      var result = await loadString(
          serverUri.resolve("/dglux5-login.htm"),
          "username=${username}&password=${password}",
          "application/x-www-form-urlencoded"
      );
      if (result.trim().isNotEmpty) {
        return false;
      }
      sessionStr = await loadString(serverUri.resolve(config['sessionUrl']));
      dgbox = true;
    }
    Map session = JSON.decode(sessionStr);

    if (session['connection'] != null && session['connection'].contains("async")) {
      service = new DGDataServiceAsync(serverUrl, serverUri.resolve(config['dataUrl']).toString(), serverUri.resolve(config['dbUrl']).toString(), this);
    } else {
      service = new DGDataService(serverUrl, serverUri.resolve(config['dataUrl']).toString(), serverUri.resolve(config['dbUrl']).toString(), this);
    }

    service.dgbox = dgbox;

    return true;
  }

  bool dgbox = false;
}
