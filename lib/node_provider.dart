part of dglux.dgapi;

class DgApiNodeProvider extends SimpleNodeProvider implements SerializableNodeProvider {
  IPermissionManager permissions = new DummyPermissionManager();
  Map<String, DGDataService> services = {};

  Map<String, LocalNode> nodes = new Map<String, LocalNode>();

  LocalNode getNode(String path) {
    if (nodes.containsKey(path)) {
      return nodes[path];
    }

    // don't cache in nodes map, it's only for running subscription
    // other nodes are just used once and throw away
    var conn = path.split("/").take(2).join("/").substring(1);

    if (!services.containsKey(conn)) {
      return new SimpleNode(path);
    }

    var n = new DgApiNode(conn, path, this);
    n.rpath = n.path.substring("/${conn}".length);
    return n;
  }

  LocalNode operator [](String path) {
    return getNode(path);
  }

  /// register node for subscribe or list api
  void registerNode(String conn, DgApiNode node) {
    if (nodes.containsKey(node.path)) {
      if (nodes[node.path] == node) {
        return;
      }
      print('error: OldApiNodeProvider.addSubscribeNode, node mismatch');
    }
    nodes[node.path] = node;
  }

  void unregisterNode(DgApiNode node) {
    if (nodes[node.path] == node) {
      nodes.remove(node.path);
    }
  }

  @override
  void init([Map m, Map profiles]) {
    if (m == null) return;
    var names = m.keys.where((it) => !it.startsWith(r"$") && it != "Add_Connection").toList();
    nx = names.length;
    for (var n in names) {
      var url = m[n][r"$$dgapi_url"];
      var username = m[n][r"$$dgapi_username"];
      var password = m[n][r"$$dgapi_password"];
      var resolveIcons = m[n][r"$$dgapi_icons"];

      if (resolveIcons == null) {
        resolveIcons = false;
      }

      IOldApiConnection connection = new OldApiBaseAuthConnection(url, username, password, resolveIcons);

      int tryAgain = 0;

      void setup() {
        services[n] = connection.service;
        SimpleNode node = new SimpleNode("/");

        node.load({
          r"$$dgapi_url": url,
          r"$$dgapi_username": username,
          r"$$dgapi_password": password,
          r"$$dgapi_icons": resolveIcons
        });

        nodes["/"].addChild(n, node);
      }

      void makeTry() {
        connection.login().then((_) {
          print("Connection to '${n}' succeeded.");
          setup();
          if (tryAgain == 0) {
            ll++;
          }
        }).catchError((e) {
          print("Warning: Failed to connect for connection ${n}: ${e}");
          if (tryAgain == 0) {
            ll++;
          }

          tryAgain += tryAgain * 2;

          if (tryAgain >= 60) {
            tryAgain = 2;
          }

          Scheduler.after(new Duration(seconds: tryAgain), () {
            makeTry();
          });
        });
      }

      makeTry();
    }
  }

  int ll = 0;
  int nx = -1;

  @override
  Map save() {
    var m = {
      r"$is": "node"
    };

    for (var x in services.keys) {
      var c = nodes["/"].children[x].configs;
      m[x] = {
        r"$$dgapi_url": c[r"$$dgapi_url"],
        r"$$dgapi_username": c[r"$$dgapi_username"],
        r"$$dgapi_password": c[r"$$dgapi_password"],
        r"$$dgapi_icons": c[r"$$dgapi_icons"]
      };
    }

    return m;
  }

  @override
  LocalNode operator ~() {
    return getNode("/");
  }

  Responder createResponder(String dsId) {
    return new Responder(this, dsId);
  }
}
