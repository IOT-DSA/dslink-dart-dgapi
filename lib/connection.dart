part of dglux.dgapi;

abstract class IOldApiConnection{
  Future<bool> login();
  Future<String> loadString(Uri uri, [String post]);
  DGDataService get service;
}

List foldList(List a, List b) {
  return a..addAll(b);
}


class OldApiBaseAuthConnection implements IOldApiConnection {
  final String serverUrl;
  final String username;
  final String password;
  Uri serverUri;
  String authString;
  DGDataService service;
  OldApiBaseAuthConnection(this.serverUrl, this.username, this.password) {
    serverUri = Uri.parse(serverUrl);
    authString = CryptoUtils.bytesToBase64(UTF8.encode('$username:$password'));
  }

  Future<String> loadString(Uri uri, [String post]) async {
    HttpClient loader = new HttpClient();
    HttpClientRequest req;
    if (post != null) {
      req = await loader.postUrl(uri);
    } else {
      req = await loader.getUrl(uri);
    }
    authRequest(req);
    if (post != null) {
      req.add(UTF8.encode(post));
    }
    HttpClientResponse resp = await req.close();
    addCookie(resp.headers.value('set-cookie'));
    List configBytes = await resp.fold([], foldList);
    return UTF8.decode(configBytes);
  }
  void authRequest(HttpClientRequest req) {
    req.headers.add('Authorization', 'Basic ZGdTdXBlcjpkZ2x1eDEyMzQ=');
    if (serverCookie != null) {
      req.headers.add('cookie', serverCookie);
    }
  }
  String serverCookie;
  void addCookie(String cookie){
    if (cookie != null) {
      serverCookie = cookie.split(';').where((str)=>!str.contains('path=')).join(';');
    }
  }

  Future<bool> login() async{
    String configStr = await loadString(serverUri.resolve('dgconfig.json'));
    Map config = JSON.decode(configStr);
    String sessionStr = await loadString(serverUri.resolve(config['sessionUrl']));
    Map session = JSON.decode(sessionStr);

    if (session['connection'] is String &&
    session['connection'].contains('async')) {
//      service = new DGRefApiDataServiceAsync(serverUrl,
//      serverUri.resolve(config['dataUrl']).toString(),
//      serverUri.resolve(config['dbUrl']).toString());
    } else {
      service = new DGDataService(serverUrl,
      serverUri.resolve(config['dataUrl']).toString(),
      serverUri.resolve(config['dbUrl']).toString(), this);
    }
    return true;
  }
}