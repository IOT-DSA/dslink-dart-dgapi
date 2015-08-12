part of dglux.dgapi;

class DgApiNodeProvider extends SimpleNodeProvider implements SerializableNodeProvider {
  IPermissionManager permissions = new DummyPermissionManager();
  Map<String, DGDataService> services = {};

  @override
  Map<String, LocalNode> nodes = new Map<String, LocalNode>();

  @override
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

    if (path == "/${conn}") {
      if (nodes.containsKey("/${conn}/dbQuery")) {
        n.children["dbQuery"] = nodes["/${conn}/dbQuery"];
      }

      if (nodes.containsKey("/${conn}/Delete_Connection")) {
        n.children["Delete_Connection"] = nodes["/${conn}/Delete_Connection"];
      }
    }

    return n;
  }

  @override
  LocalNode getOrCreateNode(String path, [bool addToTree]) {
    return getNode(path);
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

  void addConnection(String name, String url, String username, String password) {
    var n = name;

    IOldApiConnection connection = new OldApiBaseAuthConnection(url, username, password);

    int tryAgain = 0;

    void setup() {
      services[n] = connection.service;
      SimpleNode node = new SimpleNode("/", this);

      node.load({
        r"$$dgapi_url": url,
        r"$$dgapi_username": username,
        r"$$dgapi_password": password
      });

      var dbQueryNode = new SimpleActionNode("/${n}/dbQuery", (Map<String, dynamic> params) {
        var r = new AsyncTableResult();
        var db = params["db"];
        var query = params["query"];
        connection.service.queryDatabase(db, query).then((result) {
          r.columns = result["columns"];
          r.update(result["rows"], StreamStatus.closed);
        }).catchError((e) {
          r.close();
        });

        return r;
      }, this);

      var conn = n;

      var deleteConnectionNode = new SimpleActionNode("/${conn}/Delete_Connection", (Map<String, dynamic> params) {
        if (connection.service._watchTimer != null) {
          connection.service._watchTimer.cancel();
        }

        removeNode("/${conn}");
        nodes.keys.toList().forEach((path) {
          if (path == "/${conn}" || path.startsWith("/${conn}/")) {
            nodes.remove(path);
          }
        });
        saveLink();
      });

      dbQueryNode.load({
        r"$name": "Query Database",
        r"$invokable": "write",
        r"$params": [
          {
            "name": "db",
            "type": "enum[]"
          },
          {
            "name": "query",
            "type": "string"
          }
        ],
        r"$result": "table",
        r"$columns": []
      });

      deleteConnectionNode.load({
        r"$name": "Delete Connection",
        r"$invokable": "write",
        r"$result": "values"
      });

      node.addChild("dbQuery", dbQueryNode);
      nodes["/${n}/dbQuery"] = dbQueryNode;
      node.addChild("Delete_Connection", deleteConnectionNode);
      nodes["/${n}/Delete_Connection"] = deleteConnectionNode;

      connection.service.listDatabases().then((dbs) {
        (dbQueryNode.configs[r"$params"] as List)[0]["type"] = buildEnumType(dbs);
        dbQueryNode.listChangeController.add(r"$params");
      });

      nodes["/"].addChild(n, node);
    }

    var retries = 0;
    void makeTry() {
      retries++;
      connection.loginWithError().then((_) {
        print("Connection to '${n}' succeeded.");
        setup();
        if (tryAgain == 0) {
          ll++;
        }
        nx++;
      }).catchError((e) {
        if (retries < 5) {
          print("Warning: Failed to connect for connection ${n}: ${e}");
        }

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

  Map<String, IconModel> icons = {};

  @override
  void init([Map m, Map profiles]) {
//    nodes["/sys/getIcon"] = sys.children[r"getIcon"] = new SimpleActionNode("/sys/getIcon", (Map<String, dynamic> params) async {
//      var p = params["Path"];
//
//      if (icons.containsKey(p)) {
//        var bytes = await icons[p].fetch();
//        return {
//          "Icon": ByteDataUtil.fromList(bytes)
//        };
//      } else {
//        return {
//          "Icon": ByteDataUtil.fromList([])
//        };
//      }
//    }, this)..load({
//      r"$invokable": "read",
//      r"$columns": [
//        {
//          "name": "Icon",
//          "type": "bytes"
//        }
//      ],
//      r"$params": [
//        {
//          "name": "Path",
//          "type": "string"
//        }
//      ]
//    });

    if (m == null) return;
    var names = m.keys.where((it) => !it.startsWith(r"$") && it != "Add_Connection").toList();
    nx = names.length;
    for (var n in names) {
      var url = m[n][r"$$dgapi_url"];
      var username = m[n][r"$$dgapi_username"];
      var password = m[n][r"$$dgapi_password"];

      addConnection(n, url, username, password);
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
    return new Responder(this);
  }
}

class IconModel {
  final DGDataService service;
  final String path;

  IconModel(this.service, this.path);

  Future<List<int>> fetch() async {
    return await service.connection.loadBytes(Uri.parse(service.resolveIcon(path)));
  }
}
